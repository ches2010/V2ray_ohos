#include "napi/native_api.h"
#include <dlfcn.h>
#include <hilog/log.h>
#include <mutex>
#include <string>

#define LOG_TAG "V2RayNG"
#define LOGI(...) ((void)OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, LOG_TAG, __VA_ARGS__))
#define LOGE(...) ((void)OH_LOG_Print(LOG_APP, LOG_ERROR, 0x0000, LOG_TAG, __VA_ARGS__))

// ---------------------------------------------------------------------------
// libXray C 桥（由 ohos-go 从 2dust/AndroidLibXrayLite 交叉编译产出 libxray_ohos.so）
//
// Android 版 v2rayNG 通过 gomobile aar 调用同一批 Go 接口：
//   libv2ray.Libv2ray.initCoreEnv / checkVersionX / measureOutboundDelay
//   libv2ray.CoreController.startLoop(config, tunFd) / stopLoop()
// 鸿蒙侧预期导出的 C 符号如下；若实际产物符号不同，仅需调整 kSym* 常量。
// ---------------------------------------------------------------------------
static const char *K_LIB_NAME = "libxray_ohos.so";
static const char *K_SYM_INIT_ENV = "xray_init_core_env";
static const char *K_SYM_VERSION = "xray_check_version";
static const char *K_SYM_MEASURE = "xray_measure_outbound_delay";
static const char *K_SYM_START = "xray_start_loop";
static const char *K_SYM_STOP = "xray_stop_loop";
static const char *K_SYM_RUNNING = "xray_is_running";

typedef void (*fn_init_core_env)(const char *assetPath, const char *deviceId);
typedef const char *(*fn_check_version)();
typedef long long (*fn_measure_delay)(const char *config, const char *testUrl);
typedef int (*fn_start_loop)(const char *config, int tunFd);
typedef void (*fn_stop_loop)();
typedef int (*fn_is_running)();

static void *g_lib = nullptr;
static fn_init_core_env g_initEnv = nullptr;
static fn_check_version g_version = nullptr;
static fn_measure_delay g_measure = nullptr;
static fn_start_loop g_start = nullptr;
static fn_stop_loop g_stop = nullptr;
static fn_is_running g_running = nullptr;
static std::once_flag g_load_once;

static void LoadLib() {
    g_lib = dlopen(K_LIB_NAME, RTLD_NOW | RTLD_LOCAL);
    if (g_lib == nullptr) {
        LOGE("dlopen %{public}s failed: %{public}s", K_LIB_NAME, dlerror());
        return;
    }
    g_initEnv = reinterpret_cast<fn_init_core_env>(dlsym(g_lib, K_SYM_INIT_ENV));
    g_version = reinterpret_cast<fn_check_version>(dlsym(g_lib, K_SYM_VERSION));
    g_measure = reinterpret_cast<fn_measure_delay>(dlsym(g_lib, K_SYM_MEASURE));
    g_start = reinterpret_cast<fn_start_loop>(dlsym(g_lib, K_SYM_START));
    g_stop = reinterpret_cast<fn_stop_loop>(dlsym(g_lib, K_SYM_STOP));
    g_running = reinterpret_cast<fn_is_running>(dlsym(g_lib, K_SYM_RUNNING));
    LOGI("libXray symbols loaded: env=%d ver=%d measure=%d start=%d stop=%d running=%d",
         g_initEnv != nullptr, g_version != nullptr, g_measure != nullptr,
         g_start != nullptr, g_stop != nullptr, g_running != nullptr);
}

static bool EnsureLoaded() {
    std::call_once(g_load_once, LoadLib);
    return g_lib != nullptr;
}

// ---------------------------------------------------------------------------
// NAPI exports
// ---------------------------------------------------------------------------
static napi_value InitCoreEnv(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (!EnsureLoaded() || g_initEnv == nullptr) {
        LOGE("initCoreEnv: libxray_ohos.so not available");
        return nullptr;
    }
    char assetPath[512] = {0};
    char deviceId[128] = {0};
    size_t n = 0;
    napi_get_value_string_utf8(env, args[0], assetPath, sizeof(assetPath), &n);
    napi_get_value_string_utf8(env, args[1], deviceId, sizeof(deviceId), &n);
    g_initEnv(assetPath, deviceId);
    LOGI("initCoreEnv done");
    return nullptr;
}

static napi_value CheckVersion(napi_env env, napi_callback_info info) {
    napi_value result;
    std::string ver = "unavailable";
    if (EnsureLoaded() && g_version != nullptr) {
        ver = g_version();
    }
    napi_create_string_utf8(env, ver.c_str(), ver.size(), &result);
    return result;
}

static napi_value MeasureOutboundDelay(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_value result;
    long long ms = -1;
    if (EnsureLoaded() && g_measure != nullptr) {
        char config[65536] = {0};
        char url[1024] = {0};
        size_t n = 0;
        napi_get_value_string_utf8(env, args[0], config, sizeof(config), &n);
        napi_get_value_string_utf8(env, args[1], url, sizeof(url), &n);
        ms = g_measure(config, url);
    }
    napi_create_double(env, static_cast<double>(ms), &result);
    return result;
}

static napi_value StartLoop(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = false;
    if (EnsureLoaded() && g_start != nullptr) {
        char config[131072] = {0};
        size_t n = 0;
        napi_get_value_string_utf8(env, args[0], config, sizeof(config), &n);
        int tunFd = -1;
        napi_get_value_int32(env, args[1], &tunFd);
        ok = g_start(config, tunFd) != 0;
        LOGI("startLoop fd=%{public}d -> %{public}s", tunFd, ok ? "ok" : "failed");
    } else {
        LOGE("startLoop: libxray_ohos.so not available");
    }
    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

static napi_value StopLoop(napi_env env, napi_callback_info info) {
    if (EnsureLoaded() && g_stop != nullptr) {
        g_stop();
        LOGI("stopLoop done");
    }
    return nullptr;
}

static napi_value IsRunning(napi_env env, napi_callback_info info) {
    bool running = false;
    if (EnsureLoaded() && g_running != nullptr) {
        running = g_running() != 0;
    }
    napi_value result;
    napi_get_boolean(env, running, &result);
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
