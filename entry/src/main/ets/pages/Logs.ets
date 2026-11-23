import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import pasteboard from '@ohos.pasteboard';
import { RuntimeSnapshot, isRuntimeRunning } from '../core/RuntimeSnapshot';
import { RuntimeStore } from '../core/RuntimeStore';

class DiagnosticLine {
  label: string;
  value: string;
  color: string;
  constructor(label: string, value: string, color: string = '#E5EDFF') {
    this.label = label;
    this.value = value;
    this.color = color;
  }
}

/** 所有核心状态来自 VPN 进程快照；查看日志不会在 UI 进程 dlopen 核心。 */
@Entry
@Component
struct LogsPage {
  @State snapshot: RuntimeSnapshot = new RuntimeSnapshot();
  @State lines: DiagnosticLine[] = [];
  @State logText: string = '';
  @State errorText: string = '';
  @State hasSnapshot: boolean = false;
  @StorageProp('sysBarHeightPx') sysBarPx: number = 0;
  @StorageProp('navBarHeightPx') navBarPx: number = 0;
  private timer: number = -1;

  aboutToAppear(): void { this.startReader(); }
  onPageShow(): void { this.startReader(); }
  onPageHide(): void { this.stopReader(); }
  aboutToDisappear(): void { this.stopReader(); }

  private startReader(): void {
    this.collect();
    if (this.timer < 0) this.timer = setInterval(() => { this.collect(); }, 1500);
  }

  private stopReader(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private probePart(key: string, text: string): string {
    for (let part of text.split(' ')) {
      if (part.startsWith(key + ':')) {
        let value: string = part.substring(key.length + 1);
        if (value === 'ok') return '已完成';
        if (value === 'accepted') return '请求已接受（不等于联网）';
        if (value === 'fail') return '失败 / 超时';
        if (value === 'pending') return '尚未完成';
        return '已收到 HTTP ' + value;
      }
    }
    return '尚未运行';
  }

  collect(): void {
    let context: common.Context = getContext(this) as common.Context;
    let value: RuntimeSnapshot | null = RuntimeStore.read(context);
    this.hasSnapshot = value !== null;
    let s: RuntimeSnapshot = value ?? new RuntimeSnapshot();
    this.snapshot = s;
    let alive: boolean = isRuntimeRunning(value);
    let rows: DiagnosticLine[] = [];
    rows.push(new DiagnosticLine('状态来源', 'VPN 进程（统一快照）'));
    rows.push(new DiagnosticLine('VPN 状态', alive ? '核心运行中' : s.state, alive ? '#22C55E' : '#EAB308'));
    rows.push(new DiagnosticLine('系统 TUN', s.active ? '本会话仍持有' : '未持有'));
    rows.push(new DiagnosticLine('当前阶段', s.stage));
    rows.push(new DiagnosticLine('心跳时间', s.updatedAt > 0 ? new Date(s.updatedAt).toLocaleTimeString() : '无'));
    rows.push(new DiagnosticLine('Xray 库', s.native.xrayLibLoaded ? '已加载' : '未加载'));
    rows.push(new DiagnosticLine('tun2socks 库', s.native.hevLibLoaded ? '已加载' : '未加载'));
    rows.push(new DiagnosticLine('Xray 已启动', s.native.xrayStarted ? '是' : '否'));
    rows.push(new DiagnosticLine('hev 线程', s.native.hevExited ? '已退出，rc=' + s.native.hevRc : (alive ? '运行中' : '未启动')));
    rows.push(new DiagnosticLine('Xray 版本', s.native.coreVersion || '尚未读取'));
    rows.push(new DiagnosticLine('运行包标记', s.native.buildSignature || '尚未启动新包'));
    rows.push(new DiagnosticLine('TUN 发包 / 字节', s.native.tunTxPackets + ' / ' + s.native.tunTxBytes));
    rows.push(new DiagnosticLine('TUN 收包 / 字节', s.native.tunRxPackets + ' / ' + s.native.tunRxBytes));
    rows.push(new DiagnosticLine('防 VPN 回环', s.excludedBundle || '未配置'));
    rows.push(new DiagnosticLine('geoip.dat 当前文件', RuntimeStore.fileReady(context.filesDir + '/assets/geoip.dat') ? '已就绪' : '未下载'));
    rows.push(new DiagnosticLine('geosite.dat 当前文件', RuntimeStore.fileReady(context.filesDir + '/assets/geosite.dat') ? '已就绪' : '未下载'));
    rows.push(new DiagnosticLine('启动时 Geo 分流', s.geoRulesEnabled ? '已启用' : '未启用（下载后需重启 VPN）'));
    rows.push(new DiagnosticLine('启动节点', s.nodeName || '未选择'));
    rows.push(new DiagnosticLine('协议 / 传输 / TLS', s.protocol + ' / ' + s.transport + ' / ' + s.tls));
    rows.push(new DiagnosticLine('实际路由', s.routeMode === 1 ? '绕过局域网及大陆' : '全局代理'));
    rows.push(new DiagnosticLine('Mux / 嗅探', (s.muxEnabled ? '开' : '关') + ' / ' + (s.sniffingEnabled ? '开' : '关')));
    rows.push(new DiagnosticLine('探测状态', s.native.probeRunning ? '进行中' : '已结束 / 未运行'));
    rows.push(new DiagnosticLine('SOCKS 入站', this.probePart('inbound', s.native.fullSelfTest)));
    rows.push(new DiagnosticLine('SOCKS 握手', this.probePart('handshake', s.native.fullSelfTest)));
    rows.push(new DiagnosticLine('CONNECT 回复', this.probePart('connect', s.native.fullSelfTest)));
    rows.push(new DiagnosticLine('代理 HTTP 往返', this.probePart('http', s.native.fullSelfTest)));
    this.lines = rows;
    this.errorText = RuntimeStore.redact(s.errorText || s.native.lastError || '未记录核心错误；探测失败请查看下方日志');
    let xray: string = RuntimeStore.readTail(context.filesDir + '/xray-error.log', 12000);
    let hev: string = RuntimeStore.readTail(context.filesDir + '/hev.log', 8000);
    this.logText = RuntimeStore.redact(s.native.events + '\n--- Xray 错误日志 ---\n' + xray + '\n--- hev 日志 ---\n' + hev);
  }

  private copyLog(): void {
    let text: string = RuntimeStore.redact(JSON.stringify(this.snapshot, null, 2) + '\n' + this.logText);
    let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '已复制本地诊断（UUID/常见凭据字段已隐藏）' });
    }).catch(() => { promptAction.showToast({ message: '复制失败' }); });
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Text('←').fontSize(22).fontColor('#E5EDFF').onClick(() => { router.back(); })
        Text('日志诊断').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
        Blank()
        Button('刷新').fontSize(12).height(32).backgroundColor('#1D2A44').onClick(() => { this.collect(); })
        Button('复制').fontSize(12).height(32).backgroundColor('#1D2A44').onClick(() => { this.copyLog(); })
      }
      .width('100%').padding({ left: 16, right: 16, top: px2vp(this.sysBarPx) + 12, bottom: 8 })
      Scroll() {
        Column({ space: 8 }) {
          Text(this.hasSnapshot ? '以下为 VPN 进程的实时状态，不混用 UI 进程状态。' : '尚未收到新协议的 VPN 会话，请启动连接。')
            .fontSize(12).fontColor('#94A3B8').width('100%')
          ForEach(this.lines, (row: DiagnosticLine) => {
            Row({ space: 8 }) {
              Text(row.label).fontSize(12).fontColor('#8A94A8').width('44%')
              Text(row.value).fontSize(12).fontColor(row.color).layoutWeight(1)
                .textAlign(TextAlign.End).maxLines(4)
            }
            .width('100%').padding(10).borderRadius(8).backgroundColor('#151E31')
          }, (row: DiagnosticLine) => row.label + ':' + row.value)
          Text('最近核心错误').fontSize(14).fontColor('#94A3B8').width('100%')
          Text(this.errorText).fontSize(12).fontColor('#F87171').width('100%').copyOption(CopyOptions.InApp)
          Text('本地日志（末尾片段）').fontSize(14).fontColor('#94A3B8').width('100%')
          Text(this.logText || '暂无日志').fontSize(11).fontColor('#E5EDFF').width('100%').copyOption(CopyOptions.InApp)
          Text('SOCKS 探测不包含 TUN 和系统 DNS。CONNECT 成功只表示请求被接受，只有 HTTP 回复才代表数据往返。请结合 TUN 收发字节判断真实浏览器流量。')
            .fontSize(11).fontColor('#64748B').width('100%')
        }
        .padding({ left: 16, right: 16, bottom: px2vp(this.navBarPx) + 20 }).width('100%')
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor('#0B1220')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
