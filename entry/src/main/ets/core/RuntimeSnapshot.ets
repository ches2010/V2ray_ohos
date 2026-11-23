/** 唯一的 VPN 运行状态协议；由 VPN 进程发布，UI 只读取，不自行探测 native。 */
export const RUNTIME_SCHEMA: number = 2;
export const BUILD_SIGNATURE: string = 'vpn-runtime-v2-self-excluded';

export class NativeStatus {
  xrayLibLoaded: boolean = false;
  hevLibLoaded: boolean = false;
  xrayStarted: boolean = false;
  running: boolean = false;
  hevExited: boolean = false;
  hevRc: number = -1;
  probeRunning: boolean = false;
  socksSelfTest: string = '';
  fullSelfTest: string = '';
  lastError: string = '';
  coreVersion: string = '';
  buildSignature: string = '';
  tunTxPackets: number = 0;
  tunTxBytes: number = 0;
  tunRxPackets: number = 0;
  tunRxBytes: number = 0;
  events: string = '';
}

export class RuntimeSnapshot {
  schema: number = RUNTIME_SCHEMA;
  sessionId: string = '';
  state: string = 'stopped'; // starting | running | stopping | stopped | error
  stage: string = 'idle';
  updatedAt: number = 0;
  active: boolean = false; // 系统 TUN 是否仍由本会话持有；与 HTTP 探测是否成功分开
  nodeName: string = '';
  protocol: string = '';
  transport: string = '';
  tls: string = '';
  routeMode: number = 0;
  geoIpReady: boolean = false;
  geoSiteReady: boolean = false;
  geoRulesEnabled: boolean = false;
  muxEnabled: boolean = false;
  sniffingEnabled: boolean = false;
  excludedBundle: string = '';
  errorText: string = '';
  native: NativeStatus = new NativeStatus();
}

/** 只有 VPN 进程的心跳及 native 存活证据能表示已启动；探测成功不是其必要条件。 */
export function isRuntimeRunning(s: RuntimeSnapshot | null): boolean {
  if (s === null || Date.now() - s.updatedAt > 10000) {
    return false;
  }
  return s.state === 'running' && s.active && s.native.running
    && s.native.xrayStarted && !s.native.hevExited;
}
