# v2rayNG → HarmonyOS NEXT 移植报告

日期：2026-11-21 ｜ 源项目：https://github.com/2dust/v2rayNG（v2.4.0，master HEAD）

## 1. 源项目分析

### 技术栈识别
| 项 | 内容 |
|---|---|
| 项目类型 | Android 原生（Kotlin 2.4 + Jetpack Compose + Material3） |
| 模块 | `V2rayNG/`（App）、`AndroidLibXrayLite/`（Go 子模块，Xray core + tun2socks）、`hev-socks5-tunnel/`（C 子模块） |
| 核心 | libv2ray aar（gomobile），接口：`initCoreEnv / checkVersionX / measureOutboundDelay / newCoreController → startLoop(config, tunFd) / stopLoop` |
| 隧道 | Android `VpnService`（`CoreVpnService`）+ hev-socks5-tunnel |
| 存储 | MMKV |
| 网络 | OkHttp |
| 扫码 | CameraX + zxing |
| 规模 | 194 个 Kotlin 源文件，35+ Activity/Service |

### 依赖的系统能力
VPN（核心）、网络访问、通知、开机广播、快捷方式/磁贴、文件存储、相机（扫码）。

## 2. 移植路线（一句话）

**ArkTS + ArkUI 全量重写 UI 与业务逻辑；Go 核心（Xray + tun2socks）用 ohos-go 交叉编译为 .so 经 NAPI 复用；Android VpnService 映射为鸿蒙 `VpnExtensionAbility`（@kit.NetworkKit，API 11+）。**

## 3. 能力映射

| v2rayNG（Android） | 鸿蒙实现 | 状态 |
|---|---|---|
| CoreVpnService（VpnService.establish） | VpnTunnelAbility（VpnConnection.create → tun fd） | ✅ 已实现 |
| libv2ray aar（Go/gomobile） | libxray_ohos.so（ohos-go）+ NAPI（dlopen 动态加载） | ✅ 桥已实现，so 需自行编译 |
| CoreConfigManager / CoreOutboundBuilder | ConfigBuilder.ets（vless/vmess/trojan/ss/socks/http + ws/grpc + tls/reality） | ✅ 精简实现 |
| MMKV ProfileItem 存储 | ProfileStore.ets（preferences + JSON） | ✅ 已实现 |
| 分享链接/订阅解析（V2rayConfig 格式） | Profile.ets parseShareLink + 订阅 base64/明文 | ✅ 已实现 |
| MainActivity（Compose） | pages/Index.ets（连接按钮/节点列表/状态） | ✅ 已实现 |
| 各协议编辑 Activity | pages/ServerEdit.ets（统一表单） | ✅ 已实现 |
| OkHttp 订阅下载 | @kit.NetworkKit http | ✅ 已实现 |
| 测速（CoreTestService） | LibXray.measureOutboundDelay | ✅ 接口已接 |
| 分应用代理（AppPicker） | VpnConfig.blockedApplications/trustedApplications | 🟡 数据通路已留，UI 未做 |
| 通知（前台服务通知） | notificationManager | ⬜ 未实现 |
| 扫码导入 | @kit.ScanKit | ⬜ 未实现 |
| 开机自启/磁贴/快捷方式/Tasker | commonEventManager / 卡片 | ⬜ 未实现 |
| 路由分流（RoutingSetting）、自定义配置、代理链、WireGuard/Hysteria2/MASQUE | — | ⬜ 未实现（第二阶段） |
| geoip/geosite 路由规则 | 沿用 Xray 配置（geoip:private 已内置），dat 需下载到沙箱 assets | 🟡 框架就绪 |

## 4. 已验证 / 未验证

- ✅ 工程结构与 Stage 模型规范一致；VPN API（startVpnExtensionAbility / stopVpnExtensionAbility / VpnConnection.create→fd / protect / destroy / generateVpnId）均按官方 API 参考核对（API 11 基线，generateVpnId/destroy(vpnId) 为 API 20+）。
- ⚠️ **本环境无 DevEco Studio / ohos-go 工具链，代码未经过实际编译**。ArkTS 代码按 API 12 规范编写，个别 API 细节（如 VpnConfig 的 gateway/family 字段取值）以官方示例为准，编译报错时可按提示微调。
- ⬜ 真机连通性未验证：需要 libxray_ohos.so + 签名 + 真机 + 授权弹窗确认。

## 5. 风险与后续

1. **Go 核心编译是最大前置项**：ohos-go 工具链版本需与 DevEco NDK 匹配；hev-socks5-tunnel 需随 Go 库一起交叉编译（参考根目录 compile-hevtun.sh 的 Android 逻辑改写）。
2. **VPN 进程管控**：社区反馈 HarmonyOS 对 VPN 进程有较强管控（长时任务 + 权限策略），后续可加 backgroundTaskManager 长时任务与常驻通知。
3. **NAPI 符号约定**：napi_init.cpp 通过 dlopen + dlsym 加载核心，若 ohos-go 产物符号名不同，只改 `K_SYM_*` 常量。
4. **合规**：沿用 GPL-3.0；上架应用市场需自行确认平台政策。
5. **下一步建议**：通知与前台状态、分应用代理 UI、扫码导入、路由分流编辑器、Hysteria2/WireGuard（Xray 已支持）。

## 6. 交付物

```
V2rayNGHarmony/                 # 可打开构建的鸿蒙工程
  AppScope/app.json5
  build-profile.json5 / hvigorfile.ts / oh-package.json5
  entry/
    src/main/module.json5       # EntryAbility + VpnTunnelAbility(type: vpn)
    src/main/ets/pages/         # Index（主页）、ServerEdit（节点编辑）
    src/main/ets/core/          # ProfileStore / ConfigBuilder / VpnController
    src/main/ets/vpnability/    # VpnTunnelAbility（CoreVpnService 对应物）
    src/main/ets/native/        # libxray.ets（NAPI 桥）
    src/main/cpp/               # napi_init.cpp + CMakeLists.txt
V2rayNG-移植报告.md              # 本文件
```
