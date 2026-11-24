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
  // 30s 窗口：1s 心跳下偶发一次写入延迟不应把运行中的隧道翻成“启动中/异常”。
  if (s === null || Date.now() - s.updatedAt > 30000) {
    return false;
  }
  return s.state === 'running' && s.active && s.native.running
    && s.native.xrayStarted && !s.native.hevExited;
}

/** UI 每秒轮询的读取轨迹；循环/跳变时与日志页对照即可定位翻转字段。 */
export class PollTrace {
  time: string = '';
  readOk: boolean = false;
  state: string = '';
  stage: string = '';
  active: boolean = false;
  running: boolean = false;
  nativeRunning: boolean = false;
  xrayStarted: boolean = false;
  hevExited: boolean = false;
  ageMs: number = -1;
  reason: string = '';
}

export const pollTraces: PollTrace[] = [];

export function recordPollTrace(readOk: boolean, s: RuntimeSnapshot | null,
  running: boolean, ageMs: number, reason: string): void {
  let trace: PollTrace = new PollTrace();
  let now: Date = new Date();
  trace.time = now.getHours().toString().padStart(2, '0') + ':'
    + now.getMinutes().toString().padStart(2, '0') + ':'
    + now.getSeconds().toString().padStart(2, '0');
  trace.readOk = readOk;
  trace.running = running;
  trace.ageMs = ageMs;
  trace.reason = reason;
  if (s !== null) {
    trace.state = s.state;
    trace.stage = s.stage;
    trace.active = s.active;
    trace.nativeRunning = s.native.running;
    trace.xrayStarted = s.native.xrayStarted;
    trace.hevExited = s.native.hevExited;
  }
  pollTraces.push(trace);
  if (pollTraces.length > 60) {
    pollTraces.splice(0, pollTraces.length - 60);
  }
}
