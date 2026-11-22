import { socket } from '@kit.NetworkKit';
import { Profile } from '../model/Profile';

/** 单个节点测速结果 */
export class TestResult {
  id: string = '';
  ms: number = -2; // -2 = 超时/失败
}

/** 对 host:port 发起 TCP 连接并测量耗时（毫秒）。失败/超时返回 -2。 */
function tcpPing(host: string, port: number, timeoutMs: number): Promise<number> {
  return new Promise<number>((resolve: (v: number) => void) => {
    let tc = socket.constructTCPSocketInstance();
    let start = Date.now();
    let addr: socket.NetAddress = {
      address: host,
      port: port,
      family: 1
    };
    let options: socket.TCPConnectOptions = {
      address: addr,
      timeout: timeoutMs
    };
    tc.connect(options).then(() => {
      let ms = Date.now() - start;
      tc.close().catch(() => {});
      resolve(ms);
    }).catch(() => {
      tc.close().catch(() => {});
      resolve(-2);
    });
  });
}

/** 一键测速：并发对全部节点做 TCP 握手测速，逐个回调结果 */
export class SpeedTest {
  static async testAll(profiles: Profile[], concurrency: number, timeoutMs: number,
    onResult: (r: TestResult) => void): Promise<void> {
    let queue: Profile[] = [];
    for (let i = 0; i < profiles.length; i++) {
      queue.push(profiles[i]);
    }
    let workers: Promise<void>[] = [];
    for (let w = 0; w < concurrency; w++) {
      workers.push(SpeedTest.worker(queue, timeoutMs, onResult));
    }
    await Promise.all(workers);
  }

  private static async worker(queue: Profile[], timeoutMs: number,
    onResult: (r: TestResult) => void): Promise<void> {
    while (queue.length > 0) {
      let p = queue.shift();
      if (p === undefined) {
        break;
      }
      let ms = await tcpPing(p.server, p.serverPort, timeoutMs);
      let r = new TestResult();
      r.id = p.id;
      r.ms = ms;
      onResult(r);
    }
  }
}
