#include "napi/native_api.h"

#include <atomic>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <hilog/log.h>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

#define LOG_TAG "V2RayNG"
#define LOGI(...) ((void)OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, LOG_TAG, __VA_ARGS__))
#define LOGE(...) ((void)OH_LOG_Print(LOG_APP, LOG_ERROR, 0x0000, LOG_TAG, __VA_ARGS__))

// ---------------------------------------------------------------------------
// 数据面（对齐 v2rayNG CoreVpnService 的职责拆分，采用 Hey 已真机验证的配方）：
//
//   HarmonyOS VPN TUN fd
//     -> libhevsocks5tun.so   (hev-socks5-tunnel 2.9.0，纯 C，无 Go-TLS 问题)
//     -> 127.0.0.1:10808      (本地 SOCKS5 入站，端口与 ConfigBuilder.ets 对齐)
//     -> libxray.so           (libXray v26.7.28，GOOS=openharmony + TLSDESC)
//
// libxray.so 只导出 CGoInvoke/CGoFree 单一分发入口（method 见 libXray
// invoke_model.go：runXrayFromJson/stopXray/ping/xrayVersion/...）。
// 两个库均为运行期 dlopen：缺失时桥接层降级（UI 可跑，隧道不可用）。
// ---------------------------------------------------------------------------

using CGoInvokeFunc = char *(*)(char *);
using CGoFreeFunc = void (*)(char *);
using HevStartFunc = int (*)(const unsigned char *, unsigned int, int);
using HevQuitFunc = void (*)();

static std::atomic_bool g_running(false);
static std::atomic_bool g_xrayStarted(false);

static void *g_xrayLib = nullptr;
static CGoInvokeFunc g_invoke = nullptr;
static CGoFreeFunc g_free = nullptr;

static void *g_hevLib = nullptr;
static HevStartFunc g_hevStart = nullptr;
static HevQuitFunc g_hevQuit = nullptr;
static std::thread g_hevThread;

static std::string g_assetDir;  // geoip/geosite.dat 资源目录
static std::string g_workDir;   // 可写目录（ping 临时配置文件）
static std::mutex g_assetMutex;
static bool g_assetEnvSet = false;
static std::string g_lastError; // 最近一次数据面错误（供日志诊断页展示）

static const int kVpnSocksPort = 10808; // 与 entry/src/main/ets/core/ConfigBuilder.ets 对齐

// ---------------------------------------------------------------------------
// 基础工具
// ---------------------------------------------------------------------------
static std::string DirName(const std::string &path) {
    size_t pos = path.find_last_of('/');
    if (pos == std::string::npos) {
        return ".";
    }
    if (pos == 0) {
        return "/";
    }
    return path.substr(0, pos);
}

// 与 Hey 一致：优先从可执行文件同目录加载（HAP 的 native libs 目录），再按裸名加载。
static void *DlopenLib(const char *name) {
    std::string exe = "/proc/self/exe";
    char buf[1024] = {0};
    ssize_t n = readlink(exe.c_str(), buf, sizeof(buf) - 1);
    if (n > 0) {
        buf[n] = '\0';
        std::string dir = DirName(buf);
        std::string p1 = dir + "/" + name;
        void *h = dlopen(p1.c_str(), RTLD_LAZY | RTLD_LOCAL);
        if (h != nullptr) {
            return h;
        }
        std::string p2 = dir + "/../" + name;
        h = dlopen(p2.c_str(), RTLD_LAZY | RTLD_LOCAL);
        if (h != nullptr) {
            return h;
        }
    }
    return dlopen(name, RTLD_LAZY | RTLD_LOCAL);
}

static std::string JsonEscape(const std::string &in) {
    std::string out;
    out.reserve(in.size() + 16);
    for (char c : in) {
        switch (c) {
            case '"':
                out += "\\\"";
                break;
            case '\\':
                out += "\\\\";
                break;
            case '\n':
                out += "\\n";
                break;
            case '\r':
                out += "\\r";
                break;
            case '\t':
                out += "\\t";
                break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += c;
                }
        }
    }
    return out;
}

// ---------------------------------------------------------------------------
// libxray.so：CGoInvoke/CGoFree 分发入口
// ---------------------------------------------------------------------------
static bool EnsureXray() {
    if (g_xrayLib != nullptr && g_invoke != nullptr && g_free != nullptr) {
        return true;
    }
    g_xrayLib = DlopenLib("libxray.so");
    if (g_xrayLib == nullptr) {
        const char *err = dlerror();
        LOGE("dlopen libxray.so failed: %{public}s", err != nullptr ? err : "unknown");
        g_lastError = "dlopen libxray.so failed: " + std::string(err != nullptr ? err : "unknown")
                          + "（HAP 内缺少核心库，请使用带 cores 的构建）";
        return false;
    }
    g_invoke = reinterpret_cast<CGoInvokeFunc>(dlsym(g_xrayLib, "CGoInvoke"));
    g_free = reinterpret_cast<CGoFreeFunc>(dlsym(g_xrayLib, "CGoFree"));
    if (g_invoke == nullptr || g_free == nullptr) {
        LOGE("libxray.so missing CGoInvoke/CGoFree exports");
        g_lastError = "libxray.so missing CGoInvoke/CGoFree exports";
        return false;
    }
    LOGI("libxray.so loaded (CGoInvoke dispatch)");
    return true;
}

// method + payload(JSON 对象文本) -> 响应信封 {"success":...,"data":...,"error":"..."}
static bool InvokeXray(const std::string &method, const std::string &payloadJson,
                       std::string &outResponse, std::string &err) {
    if (!EnsureXray()) {
        err = "libxray.so unavailable.";
        return false;
    }
    std::string request = "{\"apiVersion\":1,\"method\":\"" + method + "\",\"payload\":" +
                          (payloadJson.empty() ? "{}" : payloadJson) + "}";
    std::vector<char> buffer(request.begin(), request.end());
    buffer.push_back('\0');
    char *raw = g_invoke(buffer.data());
    if (raw == nullptr) {
        err = "CGoInvoke(" + method + ") returned null.";
        return false;
    }
    outResponse.assign(raw);
    g_free(raw);
    return true;
}

static bool InvokeSuccess(const std::string &response, std::string &err) {
    if (response.find("\"success\":true") != std::string::npos) {
        return true;
    }
    size_t key = response.find("\"error\":\"");
    if (key != std::string::npos) {
        size_t start = key + 9;
        size_t end = response.find('"', start);
        err = response.substr(start, end == std::string::npos ? std::string::npos : end - start);
    }
    if (err.empty()) {
        err = "libXray call failed.";
    }
    return false;
}

// 从响应里提取某整数键（如 "delay":123 / "version":... 不适用则 -1）
static long long ExtractIntField(const std::string &response, const std::string &key) {
    std::string needle = "\"" + key + "\":";
    size_t pos = response.find(needle);
    if (pos == std::string::npos) {
        return -1;
    }
    size_t start = pos + needle.size();
    while (start < response.size() && response[start] == ' ') {
        start++;
    }
    size_t end = start;
    while (end < response.size() &&
           (std::isdigit(static_cast<unsigned char>(response[end])) != 0 || response[end] == '-')) {
        end++;
    }
    if (end == start) {
        return -1;
    }
    return atoll(response.substr(start, end - start).c_str());
}

// 从响应里提取某字符串键（如 "data":"xray-core@..." / "version":"..."）
static std::string ExtractStringField(const std::string &response, const std::string &key) {
    std::string needle = "\"" + key + "\":\"";
    size_t pos = response.find(needle);
    if (pos == std::string::npos) {
        return "";
    }
    size_t start = pos + needle.size();
    size_t end = response.find('"', start);
    if (end == std::string::npos) {
        return "";
    }
    return response.substr(start, end - start);
}

// ---------------------------------------------------------------------------
// libhevsocks5tun.so：hev-socks5-tunnel（纯 C tun2socks）
// ---------------------------------------------------------------------------
static bool EnsureHev() {
    if (g_hevLib != nullptr && g_hevStart != nullptr && g_hevQuit != nullptr) {
        return true;
    }
    g_hevLib = DlopenLib("libhevsocks5tun.so");
    if (g_hevLib == nullptr) {
        const char *err = dlerror();
        LOGE("dlopen libhevsocks5tun.so failed: %{public}s", err != nullptr ? err : "unknown");
        g_lastError = "dlopen libhevsocks5tun.so failed: " + std::string(err != nullptr ? err : "unknown")
                          + "（HAP 内缺少核心库，请使用带 cores 的构建）";
        return false;
    }
    g_hevStart = reinterpret_cast<HevStartFunc>(dlsym(g_hevLib, "hev_socks5_tunnel_main_from_str"));
    g_hevQuit = reinterpret_cast<HevQuitFunc>(dlsym(g_hevLib, "hev_socks5_tunnel_quit"));
    if (g_hevStart == nullptr || g_hevQuit == nullptr) {
        LOGE("libhevsocks5tun.so missing hev_socks5_tunnel symbols");
        g_lastError = "libhevsocks5tun.so missing hev_socks5_tunnel symbols";
        return false;
    }
    LOGI("libhevsocks5tun.so loaded");
    return true;
}

// ---------------------------------------------------------------------------
// NAPI exports（与 entry/src/main/ets/native/libxray.ets 一一对应）
// ---------------------------------------------------------------------------
static napi_value InitCoreEnv(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char assetPath[512] = {0};
    size_t n = 0;
    napi_get_value_string_utf8(env, args[0], assetPath, sizeof(assetPath), &n);
    std::lock_guard<std::mutex> lock(g_assetMutex);
    g_assetDir = assetPath;
    g_workDir = DirName(assetPath); // filesDir（assetPath = filesDir/assets）
    // 新版 libXray 的 runXrayFromJson 不再从请求取 datDir：首次加载核心前设置资源目录。
    if (!g_assetEnvSet && !g_assetDir.empty()) {
        setenv("XRAY_LOCATION_ASSET", g_assetDir.c_str(), 1);
        g_assetEnvSet = true;
    }
    LOGI("initCoreEnv: asset=%{public}s", g_assetDir.c_str());
    return nullptr;
}

static napi_value CheckVersion(napi_env env, napi_callback_info info) {
    (void)info;
    std::string response, err;
    napi_value result;
    std::string version;
    if (InvokeXray("xrayVersion", "{}", response, err)) {
        version = ExtractStringField(response, "version");
        if (version.empty()) {
            version = ExtractStringField(response, "data");
        }
    }
    if (version.empty()) {
        version = "unknown";
    }
    napi_create_string_utf8(env, version.c_str(), version.size(), &result);
    return result;
}

static napi_value MeasureOutboundDelay(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char config[65536] = {0};
    char url[1024] = {0};
    size_t n = 0;
    napi_get_value_string_utf8(env, args[0], config, sizeof(config), &n);
    napi_get_value_string_utf8(env, args[1], url, sizeof(url), &n);

    double ms = -1;
    std::string err;
    // libXray 的 ping 走 configPath：把节点配置写到可写目录再传路径。
    if (!g_workDir.empty()) {
        std::string pingPath = g_workDir + "/v2rayng-ping-config.json";
        FILE *f = fopen(pingPath.c_str(), "wb");
        if (f != nullptr) {
            fwrite(config, 1, strlen(config), f);
            fclose(f);
            std::ostringstream payload;
            payload << "{\"configPath\":\"" << JsonEscape(pingPath) << "\","
                    << "\"timeout\":5,"
                    << "\"url\":\"" << JsonEscape(url) << "\","
                    << "\"proxy\":\"\"}";
            std::string response;
            if (InvokeXray("ping", payload.str(), response, err)) {
                long long delay = ExtractIntField(response, "delay");
                // 哨兵值：PingDelayError(10000)/PingDelayTimeout(11000) 视为失败
                if (delay > 0 && delay < 10000) {
                    ms = static_cast<double>(delay);
                }
            }
        }
    }
    if (ms < 0 && !err.empty()) {
        LOGE("ping failed: %{public}s", err.c_str());
    }
    napi_value result;
    napi_create_double(env, ms, &result);
    return result;
}

static napi_value StartLoop(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char config[131072] = {0};
    int tunFd = -1;
    size_t n = 0;
    napi_get_value_string_utf8(env, args[0], config, sizeof(config), &n);
    napi_get_value_int32(env, args[1], &tunFd);

    if (g_running.load()) {
        LOGI("startLoop: already running");
        napi_value ok;
        napi_get_boolean(env, true, &ok);
        return ok;
    }

    // 1) 启动 Xray 核心（本地 SOCKS5 入站 127.0.0.1:10808）
    if (!EnsureXray()) {
        napi_value ok;
        napi_get_boolean(env, false, &ok);
        return ok;
    }
    {
        std::lock_guard<std::mutex> lock(g_assetMutex);
        if (!g_assetEnvSet && !g_assetDir.empty()) {
            setenv("XRAY_LOCATION_ASSET", g_assetDir.c_str(), 1);
            g_assetEnvSet = true;
        }
    }
    std::string payload = "{\"configJSON\":\"" + JsonEscape(config) + "\"}";
    std::string response, err;
    if (!InvokeXray("runXrayFromJson", payload, response, err)) {
        LOGE("runXrayFromJson failed: %{public}s", err.c_str());
        g_lastError = "runXrayFromJson failed: " + err;
        napi_value ok;
        napi_get_boolean(env, false, &ok);
        return ok;
    }
    if (!InvokeSuccess(response, err)) {
        LOGE("runXrayFromJson error: %{public}s", err.c_str());
        g_lastError = "Xray config rejected: " + err;
        napi_value ok;
        napi_get_boolean(env, false, &ok);
        return ok;
    }
    g_xrayStarted.store(true);

    // 2) 启动 hev tun2socks：把 VPN TUN fd 的流量转发到本地 SOCKS 入站。
    //    hev 的 main 阻塞到 quit，放独立线程。yaml 字段见 hev-socks5-tunnel README。
    if (!EnsureHev()) {
        napi_value ok;
        napi_get_boolean(env, false, &ok);
        return ok;
    }
    std::string yaml = std::string("tunnel:\n") +
                       "  mtu: 1500\n" +
                       "socks5:\n" +
                       "  address: 127.0.0.1\n" +
                       "  port: " + std::to_string(kVpnSocksPort) + "\n" +
                       "  udp: 'udp'\n";
    if (g_hevThread.joinable()) {
        g_hevThread.join();
    }
    HevStartFunc start = g_hevStart;
    g_hevThread = std::thread([start, yaml, tunFd]() {
        int rc = start(reinterpret_cast<const unsigned char *>(yaml.data()),
                       static_cast<unsigned int>(yaml.size()), tunFd);
        LOGI("hev tunnel exited: %{public}d", rc);
    });

    g_running.store(true);
    LOGI("startLoop ok (xray + hev tun2socks), tunFd=%{public}d", tunFd);
    napi_value ok;
    napi_get_boolean(env, true, &ok);
    return ok;
}

static napi_value StopLoop(napi_env env, napi_callback_info info) {
    (void)info;
    // 1) 停 hev 数据面（quit 令阻塞的 main_from_str 返回）
    if (g_hevQuit != nullptr) {
        g_hevQuit();
    }
    if (g_hevThread.joinable()) {
        g_hevThread.join();
    }
    // 2) 停 Xray 核心
    if (g_xrayStarted.load()) {
        std::string response, err;
        if (!InvokeXray("stopXray", "{}", response, err)) {
            LOGE("stopXray failed: %{public}s", err.c_str());
        }
        g_xrayStarted.store(false);
    }
    g_running.store(false);
    LOGI("stopLoop done");
    return nullptr;
}

static napi_value IsRunning(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_get_boolean(env, g_running.load(), &result);
    return result;
}

// 诊断信息：核心库加载状态 + 最近错误（供日志页展示）
static napi_value GetCoreStatus(napi_env env, napi_callback_info info) {
    (void)info;
    std::string json = std::string("{\"xrayLibLoaded\":") + (g_xrayLib != nullptr ? "true" : "false") +
                       ",\"hevLibLoaded\":" + (g_hevLib != nullptr ? "true" : "false") +
                       ",\"xrayStarted\":" + (g_xrayStarted.load() ? "true" : "false") +
                       ",\"running\":" + (g_running.load() ? "true" : "false") +
                       ",\"assetDirSet\":" + (!g_assetDir.empty() ? "true" : "false") +
                       ",\"lastError\":\"" + JsonEscape(g_lastError) + "\"}";
    napi_value result;
    napi_create_string_utf8(env, json.c_str(), json.size(), &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"initCoreEnv", nullptr, InitCoreEnv, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"checkVersion", nullptr, CheckVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"measureOutboundDelay", nullptr, MeasureOutboundDelay, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startLoop", nullptr, StartLoop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopLoop", nullptr, StopLoop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isRunning", nullptr, IsRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCoreStatus", nullptr, GetCoreStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&demoModule);
}
