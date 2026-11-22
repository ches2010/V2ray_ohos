# V2RayNG HarmonyOS NEXT 移植工程

将 [2dust/v2rayNG](https://github.com/2dust/v2rayNG)（Android）移植为鸿蒙 Stage 模型（ArkTS + ArkUI + NAPI）工程。
完整移植决策见仓库根目录的 `../V2rayNG-移植报告.md`。

## 当前状态

- ✅ ArkTS/ArkUI 工程：主界面（连接/断开、节点列表、选中）、节点编辑（vless/vmess/trojan/ss/socks/http）、分享链接导入、订阅导入、测速入口
- ✅ VPN 隧道：`VpnTunnelAbility`（`type: "vpn"`），基于 `@kit.NetworkKit` 的 `vpnExtension` API（API 11+，Stage 模型）
- ✅ NAPI 桥：`entry/src/main/cpp/napi_init.cpp`，运行时 `dlopen("libxray_ohos.so")`
- ⚠️ **Go 核心（Xray）需要自行交叉编译为 `libxray_ohos.so` 后放入 `entry/libs/arm64-v8a/`**（见下文）。未放置时应用可编译、UI 可运行，但无法真正建立隧道。

## 构建

1. DevEco Studio 5.0+（API 12 / HarmonyOS NEXT）打开本目录。
2. `ohpm install`（或让 IDE 自动同步）。
3. 放入核心库（可选，缺省为降级模式）：

   ```
   entry/libs/arm64-v8a/libxray_ohos.so
   ```

4. 配置调试签名（File → Project Structure → Signing Configs，一键自动签名）。
5. 构建：`hvigorw assembleHap`，或 IDE 直接 Run。
6. 真机安装：`hdc install entry-default-signed.hap`。
   首次连接时系统会弹出「VPN 连接授权」对话框，需用户确认。

## Go 核心编译（产出 libxray_ohos.so）

v2rayNG 的核心是 Go 库 [2dust/AndroidLibXrayLite](https://github.com/2dust/AndroidLibXrayLite)（内含 Xray-core 与 hev-socks5-tunnel）。
Android 用 gomobile 打包成 aar；鸿蒙侧改用 [star4277/ohos-go](https://github.com/star4277/ohos-go) 工具链交叉编译：

```bash
git clone https://github.com/2dust/AndroidLibXrayLite
cd AndroidLibXrayLite
# 按 ohos-go 文档配置 OHOS_NDK / GOOS=ohos 等环境后：
# gomobile bind -target=ohos -o libxray_ohos.so ./libv2ray
```

产物需导出以下 C 符号（与本工程 `napi_init.cpp` 约定一致，符号名不同时改 `K_SYM_*` 常量即可）：

| C 符号 | 对应 Go 接口 |
|---|---|
| `xray_init_core_env(assetPath, deviceId)` | `libv2ray.Libv2ray.initCoreEnv` |
| `xray_check_version()` | `libv2ray.Libv2ray.checkVersionX` |
| `xray_measure_outbound_delay(config, url)` | `libv2ray.Libv2ray.measureOutboundDelay` |
| `xray_start_loop(config, tunFd)` | `CoreController.startLoop` |
| `xray_stop_loop()` | `CoreController.stopLoop` |
| `xray_is_running()` | 运行状态 |

geoip.dat / geosite.dat 请放到应用沙箱 `filesDir/assets/` 下（首次启动后可通过应用内下载功能补齐）。

## 许可证

本移植遵循源项目 [v2rayNG 的 GPL-3.0 许可证](https://github.com/2dust/v2rayNG/blob/master/LICENSE)，衍生分发须同样以 GPL-3.0 开源并保留版权声明。
