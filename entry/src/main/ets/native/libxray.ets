import native from 'libentry.so';

/**
 * NAPI 桥：libxray.so（libXray/Xray core, Go, CGoInvoke 分发入口）
 *          + libhevsocks5tun.so（hev-socks5-tunnel, 纯 C tun2socks）。
 *
 * 数据面（对应 v2rayNG Android 侧 libv2ray aar + hev-socks5-tunnel）：
 *   VPN TUN fd -> libhevsocks5tun.so -> 127.0.0.1:10808 (SOCKS5)
 *              -> libxray.so (runXrayFromJson 启动的本地 SOCKS 入站)
 *
 * 两个库均由 CI 交叉编译（GOOS=openharmony + TLSDESC / OHOS clang），
 * 运行期由 entry/src/main/cpp/napi_init.cpp dlopen 加载。
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

  /** 启动隧道：传入 Xray 配置 JSON 与 VPN 虚拟网卡 fd（native 侧启动 Xray SOCKS 入站 + hev tun2socks） */
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

  /** 诊断信息（JSON 字符串）：核心库加载状态 + 最近错误 */
  static getCoreStatus(): string {
    return String(native.getCoreStatus());
  }

  /** 全链路自检结果（JSON 字符串）：inbound/握手/TCP/HTTP 各阶段 */
  static getSelfTest(): string {
    return String(native.getSelfTest());
  }
}
