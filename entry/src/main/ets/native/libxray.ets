import native from 'libentry.so';

/**
 * NAPI 桥：libXray（Xray core, Go）+ tun2socks（C）。
 *
 * 对应 v2rayNG Android 侧 libv2ray aar（AndroidLibXrayLite / gomobile）：
 *   Libv2ray.initCoreEnv / checkVersionX / measureOutboundDelay
 *   CoreController.startLoop(config, tunFd) / stopLoop()
 * 鸿蒙侧由 ohos-go(https://github.com/star4277/ohos-go) 将同一 Go 源码
 * 编译为 libxray_ohos.so，本文件通过 entry/src/main/cpp/napi_init.cpp 调用。
 */
export class LibXray {
  /** 初始化核心环境（asset 路径存放 geoip/geosite.dat） */
  static initCoreEnv(assetPath: string, deviceId: string): void {
    native.initCoreEnv(assetPath, deviceId);
  }

  /** 核心版本号 */
  static checkVersion(): string {
    return String(native.checkVersion());
  }

  /** 测量节点延迟（毫秒），-1 表示失败 */
  static measureOutboundDelay(config: string, testUrl: string): number {
    return Number(native.measureOutboundDelay(config, testUrl));
  }

  /** 启动核心循环：传入 Xray 配置 JSON 与 VPN 虚拟网卡 fd（内部完成 tun 读写 + tun2socks + Xray 出站） */
  static startLoop(config: string, tunFd: number): boolean {
    return Boolean(native.startLoop(config, tunFd));
  }

  /** 停止核心循环 */
  static stopLoop(): void {
    native.stopLoop();
  }

  /** 核心是否运行中 */
  static isRunning(): boolean {
    return Boolean(native.isRunning());
  }
}
