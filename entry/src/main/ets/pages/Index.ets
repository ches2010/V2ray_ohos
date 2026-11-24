import { router, promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore, generateBarcode } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import pasteboard from '@ohos.pasteboard';
import { Profile, toShareLink } from '../model/Profile';
import { ProfileStore } from '../core/ProfileStore';
import { VpnController } from '../core/VpnController';
import { SpeedTest, TestResult } from '../core/SpeedTest';
import { XraySettings } from '../core/ProfileStore';
import { RuntimeStore } from '../core/RuntimeStore';
import { recordPollTrace } from '../core/RuntimeSnapshot';
import { RuntimeSnapshot, isRuntimeRunning } from '../core/RuntimeSnapshot';

// 霓虹终端配色（对齐 C-neon-terminal 原型）
const C_BG: string = '#070B10';
const C_PANEL: string = '#0C1219';
const C_PANEL2: string = '#0F1720';
const C_LINE: string = '#1B2735';
const C_LINE2: string = '#24384E';
const C_TXT: string = '#DCE7F2';
const C_DIM: string = '#7D8BA3';
const C_FAINT: string = '#55637A';
const C_CY: string = '#22D3EE';
const C_MG: string = '#E879F9';
const C_OK: string = '#4ADE80';
const C_WARN: string = '#FACC15';
const C_BAD: string = '#F87171';

@CustomDialog
struct LinkDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: '' });
  @Link inputText: string;
  onConfirm: (text: string) => void = (t: string) => {};

  build() {
    Column({ space: 12 }) {
      Text('导入分享链接').fontSize(17).fontWeight(FontWeight.Bold).fontColor(C_TXT)
      TextInput({ text: this.inputText, placeholder: 'vless://... / vmess://... / ss://...' })
        .type(InputType.Normal).height(48).width('100%')
        .backgroundColor('#0A1017').fontColor(C_TXT).borderColor(C_LINE2)
        .onChange((v: string) => { this.inputText = v; })
      Row({ space: 12 }) {
        Button('取消').onClick(() => { this.controller.close(); }).layoutWeight(1)
          .backgroundColor('#16222F').fontColor(C_DIM)
        Button('导入').onClick(() => { this.controller.close(); this.onConfirm(this.inputText); }).layoutWeight(1)
          .backgroundColor('rgba(34,211,238,0.16)').fontColor(C_CY)
      }.width('100%')
    }
    .padding(16).width('90%')
    .backgroundColor(C_PANEL).borderRadius(14).border({ width: 1, color: C_LINE })
  }
}

/** 分享节点：展示分享链接与二维码（generateBarcode 生成） */
@CustomDialog
struct ShareDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: '' });
  @Link linkText: string;
  @Link qrPixmap: image.PixelMap | null;

  copyLink(): void {
    let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.linkText);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '链接已复制' });
    }).catch(() => {
      promptAction.showToast({ message: '复制失败' });
    });
  }

  build() {
    Column({ space: 12 }) {
      Text('分享节点').fontSize(17).fontWeight(FontWeight.Bold).fontColor(C_TXT)
      if (this.qrPixmap !== null) {
        Image(this.qrPixmap as image.PixelMap).width(230).height(230).borderRadius(10)
      } else {
        Text('二维码生成中...').fontSize(13).fontColor(C_DIM).height(230)
      }
      Text(this.linkText).fontSize(11).fontColor(C_DIM)
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Row({ space: 12 }) {
        Button('复制链接').onClick(() => { this.copyLink(); }).layoutWeight(1)
          .backgroundColor('rgba(34,211,238,0.16)').fontColor(C_CY)
        Button('关闭').onClick(() => { this.controller.close(); }).layoutWeight(1)
          .backgroundColor('#16222F').fontColor(C_DIM)
      }.width('100%')
    }
    .padding(16).width('90%')
    .backgroundColor(C_PANEL).borderRadius(14).border({ width: 1, color: C_LINE })
  }
}

/** 节点分组（订阅分组 / 手动添加） */
export class NodeGroup {
  title: string = '';
  items: Profile[] = [];
}

@Entry
@Component
struct Index {
  @State vpnRunning: boolean = false;
  @State vpnActive: boolean = false;
  @State connectionState: string = 'stopped';
  @State errorText: string = '';
  private stateTimer: number = -1;
  private requestStartedAt: number = 0;
  private lastOkAt: number = 0;
  @State profiles: Profile[] = [];
  @State selectedId: string = '';
  @State latency: number = -1;
  @State busy: boolean = false;
  @State dialogText: string = '';
  @State testRunning: boolean = false;
  @State testDone: number = 0;
  @State testTotal: number = 0;
  @State shareLink: string = '';
  @State qrPixmap: image.PixelMap | null = null;
  @State ringAngle: number = 0;
  @State filter: string = '全部';
  @State lastTestAt: string = '--:--';
  @State upSpeed: string = '0 KB/s';
  @State downSpeed: string = '0 KB/s';
  @State sessUp: number = 0;
  @State sessDown: number = 0;
  @State uptime: string = '--:--:--';
  private prevTx: number = 0;
  private prevRx: number = 0;
  private prevAt: number = 0;
  private connectedAt: number = 0;
  private canvasCtx: CanvasRenderingContext2D | null = null;
  @StorageProp('sysBarHeightPx') sysBarPx: number = 0;
  @StorageProp('navBarHeightPx') navBarPx: number = 0;
  dialogController: CustomDialogController = new CustomDialogController({
    builder: LinkDialog({ inputText: $dialogText, onConfirm: (t: string) => { this.doImportLink(t); } }),
    customStyle: false
  });
  shareDialogController: CustomDialogController = new CustomDialogController({
    builder: ShareDialog({ linkText: $shareLink, qrPixmap: $qrPixmap }),
    customStyle: false
  });

  aboutToAppear(): void {
    this.refresh();
    this.startStateReader();
    // 圆环匀速旋转（虚线环的动态观感）
    animateTo({ duration: 9000, curve: Curve.Linear, iterations: -1, playMode: PlayMode.Normal }, () => {
      this.ringAngle = 360;
    });
  }

  onPageShow(): void {
    this.refresh();
    this.startStateReader();
  }

  onPageHide(): void {
    this.stopStateReader();
  }

  aboutToDisappear(): void {
    this.stopStateReader();
  }

  private startStateReader(): void {
    this.syncRuntime();
    if (this.stateTimer < 0) {
      this.stateTimer = setInterval(() => { this.syncRuntime(); }, 1000);
    }
  }

  private stopStateReader(): void {
    if (this.stateTimer >= 0) {
      clearInterval(this.stateTimer);
      this.stateTimer = -1;
    }
  }

  private syncRuntime(): void {
    let context: common.Context = getContext(this) as common.Context;
    let state: RuntimeSnapshot | null = RuntimeStore.read(context);
    if (state === null) {
      // 快照文件偶发不可读：35 秒内保持上一次的运行显示，不随单次读取失败翻转。
      let sticky: boolean = Date.now() - this.lastOkAt < 35000;
      recordPollTrace(false, null, this.vpnRunning && sticky, -1, RuntimeStore.lastReadError);
      if (!sticky) {
        this.vpnRunning = false;
        this.connectedAt = 0;
      }
      this.refreshUptime();
      return;
    }
    this.lastOkAt = Date.now();
    this.vpnRunning = isRuntimeRunning(state);
    recordPollTrace(true, state, this.vpnRunning, Date.now() - state.updatedAt,
      RuntimeStore.lastReadError === '' ? 'ok' : RuntimeStore.lastReadError);
    this.vpnActive = state.active || state.state === 'starting' || state.state === 'stopping';
    this.connectionState = state.state;
    this.errorText = state.errorText;
    // 由 TUN 累计字节推算实时速率 + 在线时长
    let now: number = Date.now();
    if (this.prevAt > 0 && now > this.prevAt) {
      let dt: number = (now - this.prevAt) / 1000;
      let up: number = Math.max(0, state.native.tunTxBytes - this.prevTx) / dt;
      let dn: number = Math.max(0, state.native.tunRxBytes - this.prevRx) / dt;
      this.upSpeed = this.fmtSpeed(up);
      this.downSpeed = this.fmtSpeed(dn);
    }
    this.prevTx = state.native.tunTxBytes;
    this.prevRx = state.native.tunRxBytes;
    this.prevAt = now;
    this.sessUp = state.native.tunTxBytes;
    this.sessDown = state.native.tunRxBytes;
    if (!this.vpnRunning) {
      this.connectedAt = 0;
    } else if (this.connectedAt === 0) {
      this.connectedAt = now;
    }
    this.refreshUptime();
    if (state.state !== 'starting' && state.state !== 'stopping') {
      this.busy = false;
      this.requestStartedAt = 0;
    }
    if (this.requestStartedAt > 0 && Date.now() - this.requestStartedAt > 30000) {
      this.requestStartedAt = 0;
      this.errorText = '启动超时，正在回收 VPN；请查看日志诊断';
      VpnController.stop(context).catch(() => {}).then(() => {
        this.busy = false;
        this.syncRuntime();
      });
    }
  }

  private refreshUptime(): void {
    if (this.vpnRunning && this.connectedAt > 0) {
      let sec: number = Math.floor((Date.now() - this.connectedAt) / 1000);
      let h: number = Math.floor(sec / 3600);
      let m: number = Math.floor((sec % 3600) / 60);
      let s: number = sec % 60;
      let p = (v: number): string => { return v < 10 ? '0' + v : '' + v; };
      this.uptime = p(h) + ':' + p(m) + ':' + p(s);
    } else {
      this.uptime = '--:--:--';
    }
  }

  private fmtSpeed(bps: number): string {
    if (bps >= 1024 * 1024) {
      return (bps / 1024 / 1024).toFixed(1) + ' MB/s';
    }
    if (bps >= 1024) {
      return (bps / 1024).toFixed(1) + ' KB/s';
    }
    return Math.floor(bps) + ' B/s';
  }

  private fmtBytes(b: number): string {
    if (b >= 1024 * 1024 * 1024) {
      return (b / 1024 / 1024 / 1024).toFixed(2) + ' GB';
    }
    if (b >= 1024 * 1024) {
      return (b / 1024 / 1024).toFixed(1) + ' MB';
    }
    if (b >= 1024) {
      return (b / 1024).toFixed(1) + ' KB';
    }
    return b + ' B';
  }

  async refresh(): Promise<void> {
    try {
      await ProfileStore.init(getContext(this) as common.Context);
      let loaded: Profile[] = await ProfileStore.loadProfiles();
      for (let i = 0; i < loaded.length; i++) {
        if (loaded[i].testMs === -3) {
          loaded[i].testMs = -1; // 测速中断的残留状态恢复为未测
        }
      }
      this.profiles = loaded;
      this.selectedId = await ProfileStore.loadSelectedId();
    } catch (e) {
      this.errorText = '读取节点数据失败';
    }
  }

  doImportLink(text: string): void {
    let tt = text.trim();
    if (tt === '') {
      return;
    }
    ProfileStore.addShareLink(tt).then((p: Profile | null) => {
      if (p === null) {
        promptAction.showToast({ message: '链接解析失败' });
      } else {
        promptAction.showToast({ message: '已添加: ' + p.name });
        this.refresh();
      }
    });
  }

  /** 扫码导入节点（鸿蒙统一扫码 ScanKit） */
  scanImport(): void {
    let ctx = getContext(this) as common.Context;
    scanBarcode.startScanForResult(ctx).then((result: scanBarcode.ScanResult) => {
      let text: string = result.originalValue;
      if (text === undefined || text.trim() === '') {
        promptAction.showToast({ message: '未识别到内容' });
        return;
      }
      ProfileStore.addShareLink(text.trim()).then((p: Profile | null) => {
        if (p === null) {
          promptAction.showToast({ message: '二维码不是有效的节点链接' });
        } else {
          promptAction.showToast({ message: '已添加: ' + p.name });
          this.refresh();
        }
      });
    }).catch((e: BusinessError) => {
      if (e.code !== 1600002) {
        promptAction.showToast({ message: '扫码失败: ' + e.code });
      }
    });
  }

  /** 分享节点：生成分享链接 + 二维码 */
  shareNode(p: Profile): void {
    let link = toShareLink(p);
    if (link === '') {
      promptAction.showToast({ message: '该类型暂不支持分享' });
      return;
    }
    this.shareLink = link;
    this.qrPixmap = null;
    let opts: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      width: 280,
      height: 280,
      margin: 2
    };
    generateBarcode.createBarcode(link, opts).then((pm: image.PixelMap) => {
      this.qrPixmap = pm;
      this.shareDialogController.open();
    }).catch(() => {
      this.shareDialogController.open();
    });
  }

  async toggleVpn(): Promise<void> {
    let context: common.Context = getContext(this) as common.Context;
    this.syncRuntime();
    // 即使节点被删掉、核心退出或正在启动，也必须能停止系统 VPN。
    if (this.vpnActive || this.vpnRunning || this.busy) {
      this.busy = true;
      this.connectionState = 'stopping';
      try {
        await VpnController.stop(context);
      } catch (e) {
        promptAction.showToast({ message: '断开失败，请在系统设置中断开 VPN' });
      }
      this.busy = false;
      this.syncRuntime();
      return;
    }
    let selected: Profile | null = null;
    for (let p of this.profiles) {
      if (p.id === this.selectedId) {
        selected = p;
        break;
      }
    }
    if (selected === null) {
      promptAction.showToast({ message: '请先选择一个节点' });
      return;
    }
    this.busy = true;
    this.errorText = '';
    this.connectionState = 'starting';
    this.requestStartedAt = Date.now();
    try {
      await ProfileStore.saveSelectedId(selected.id);
      let settings: XraySettings = await ProfileStore.loadSettings();
      await VpnController.start(context, selected, settings);
      // 仅表示系统接受启动请求，必须等待 VPN 进程的运行心跳。
      this.syncRuntime();
    } catch (e) {
      this.busy = false;
      this.requestStartedAt = 0;
      this.syncRuntime();
      promptAction.showToast({ message: 'VPN 启动失败，请查看日志诊断' });
    }
  }

  /** 一键测速：并发对全部节点做 TCP 握手，结果实时刷新到节点卡片 */
  runSpeedTest(): void {
    if (this.testRunning) {
      return;
    }
    if (this.profiles.length === 0) {
      promptAction.showToast({ message: '没有可测速的节点' });
      return;
    }
    this.testRunning = true;
    this.testDone = 0;
    this.testTotal = this.profiles.length;
    let cleared: Profile[] = [];
    for (let i = 0; i < this.profiles.length; i++) {
      let p = this.profiles[i];
      p.testMs = -3; // -3=测速中（-2 是 SpeedTest 的超时约定）
      cleared.push(p);
    }
    this.profiles = cleared;
    SpeedTest.testAll(this.profiles, 4, 5000, (r: TestResult) => {
      this.applyResult(r);
    }).then(() => {
      this.testRunning = false;
      let ok = 0;
      for (let i = 0; i < this.profiles.length; i++) {
        if (this.profiles[i].testMs >= 0) {
          ok++;
        }
      }
      let now: Date = new Date();
      this.lastTestAt = (now.getHours() < 10 ? '0' : '') + now.getHours() + ':' +
        (now.getMinutes() < 10 ? '0' : '') + now.getMinutes();
      promptAction.showToast({ message: '测速完成：可达 ' + ok + '/' + this.profiles.length });
      ProfileStore.saveProfiles(this.profiles);
    });
  }

  private applyResult(r: TestResult): void {
    this.testDone++;
    let list: Profile[] = [];
    for (let i = 0; i < this.profiles.length; i++) {
      let p = this.profiles[i];
      if (p.id === r.id) {
        p.testMs = r.ms;
      }
      list.push(p);
    }
    this.profiles = list;
  }

  msLabel(ms: number): string {
    if (ms === -3) {
      return '测速中';
    }
    if (ms === -1 || ms === 0) {
      return '';
    }
    if (ms < 0) {
      return '超时';
    }
    return ms + 'ms';
  }

  msColor(ms: number): string {
    if (ms === -3) {
      return '#8A94A8';
    }
    if (ms < 0) {
      return C_BAD;
    }
    if (ms < 300) {
      return C_OK;
    }
    if (ms < 800) {
      return C_WARN;
    }
    return '#F97316';
  }

  /** 从节点名提取国旗 emoji（regional indicator 对）；无则返回圆点 */
  flagOf(name: string): string {
    let arr: number[] = [];
    for (let i = 0; i < name.length; i++) {
      arr.push(name.charCodeAt(i));
    }
    for (let i = 0; i + 1 < arr.length; i++) {
      let a: number = arr[i];
      let b: number = arr[i + 1];
      if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
        return String.fromCodePoint(a, b);
      }
    }
    return '';
  }

  /** 按订阅分组：订阅组在前，手动添加的节点归入"手动添加"组放在最后 */
  getGroups(): NodeGroup[] {
    let groups: NodeGroup[] = [];
    let manual = new NodeGroup();
    manual.title = '手动添加';
    for (let i = 0; i < this.profiles.length; i++) {
      let p = this.profiles[i];
      if (this.filter !== '全部' && this.filter !== '手动添加' && p.subName !== this.filter) {
        continue;
      }
      if (this.filter === '手动添加' && p.subId !== '') {
        continue;
      }
      if (p.subId === '') {
        manual.items.push(p);
        continue;
      }
      let g: NodeGroup | null = null;
      for (let j = 0; j < groups.length; j++) {
        if (groups[j].title === p.subName) {
          g = groups[j];
          break;
        }
      }
      if (g === null) {
        g = new NodeGroup();
        g.title = p.subName === '' ? '订阅' : p.subName;
        groups.push(g);
      }
      g.items.push(p);
    }
    if (manual.items.length > 0) {
      groups.push(manual);
    }
    return groups;
  }

  selectProfile(id: string): void {
    this.selectedId = id;
    ProfileStore.saveSelectedId(id);
  }

  editProfile(p: Profile): void {
    router.pushUrl({ url: 'pages/ServerEdit', params: p });
  }

  addNew(): void {
    router.pushUrl({ url: 'pages/ServerEdit' });
  }

  openSubscriptions(): void {
    router.pushUrl({ url: 'pages/Subscription' });
  }

  removeProfile(p: Profile): void {
    let list: Profile[] = [];
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id !== p.id) {
        list.push(this.profiles[i]);
      }
    }
    this.profiles = list;
    ProfileStore.saveProfiles(list);
    if (this.selectedId === p.id) {
      this.selectedId = '';
      ProfileStore.saveSelectedId('');
    }
  }

  private selectedName(): string {
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id === this.selectedId) {
        let p = this.profiles[i];
        return p.name === '' ? p.server : p.name;
      }
    }
    return '--';
  }

  private selectedMs(): number {
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id === this.selectedId) {
        return this.profiles[i].testMs;
      }
    }
    return -1;
  }

  /** 在画布上绘制双波形（静态一次，透明度随连接状态变化） */
  private drawWave(): void {
    let ctx = this.canvasCtx;
    if (ctx === null) {
      return;
    }
    let w: number = ctx.width;
    let h: number = ctx.height;
    ctx.clearRect(0, 0, w, h);
    // 青色主波
    ctx.beginPath();
    ctx.strokeStyle = C_CY;
    ctx.lineWidth = 2;
    for (let x = 0; x <= w; x += 4) {
      let y = h * 0.62 - Math.sin(x / 26) * h * 0.22 - Math.sin(x / 11) * h * 0.10;
      if (x === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();
    // 品红副波
    ctx.beginPath();
    ctx.strokeStyle = C_MG;
    ctx.globalAlpha = 0.55;
    ctx.lineWidth = 2;
    for (let x2 = 0; x2 <= w; x2 += 4) {
      let y2 = h * 0.72 - Math.sin(x2 / 19 + 1.2) * h * 0.18 - Math.sin(x2 / 7) * h * 0.07;
      if (x2 === 0) {
        ctx.moveTo(x2, y2);
      } else {
        ctx.lineTo(x2, y2);
      }
    }
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  @Builder
  groupHeader(g: NodeGroup) {
    Row({ space: 8 }) {
      Text(g.title).fontSize(12).fontColor(C_DIM)
      Text(g.items.length + ' NODES').fontSize(10).fontColor(C_FAINT)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 8, bottom: 2 })
  }

  @Builder
  nodeRow(p: Profile) {
    Row({ space: 10 }) {
      Circle({ width: 9, height: 9 })
        .fill(p.id === this.selectedId ? C_CY : '#2C3A4D')
      Text(this.flagOf(p.name) === '' ? '' : this.flagOf(p.name)).fontSize(17)
      Column({ space: 3 }) {
        Text(p.name === '' ? p.server : p.name)
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(p.id === this.selectedId ? '#A5F3FC' : C_TXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(p.configType.toUpperCase() + ' · ' + p.server + ':' + p.serverPort)
          .fontSize(10).fontColor(C_FAINT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.msLabel(p.testMs) !== '') {
        Text(this.msLabel(p.testMs))
          .fontSize(11).fontColor(this.msColor(p.testMs))
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor('rgba(148,163,184,0.10)')
      }
      Text('分享').fontSize(11).fontColor(C_MG)
        .onClick(() => { this.shareNode(p); })
      Text('编辑').fontSize(11).fontColor(C_CY)
        .onClick(() => { this.editProfile(p); })
      Text('删除').fontSize(11).fontColor(C_BAD)
        .onClick(() => { this.removeProfile(p); })
    }
    .width('100%')
    .padding(11)
    .borderRadius(13)
    .border({ width: 1, color: p.id === this.selectedId ? 'rgba(34,211,238,0.6)' : C_LINE })
    .backgroundColor(p.id === this.selectedId ? 'rgba(34,211,238,0.08)' : 'rgba(12,18,25,0.85)')
    .onClick(() => { this.selectProfile(p.id); })
  }

  build() {
    Stack() {
      // 主列
      Column() {
        // 顶栏
        Row() {
          Column({ space: 2 }) {
            Text('V2RAY//NG').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#E6F6FB')
              .letterSpacing(1)
            Text('PROXY·TERMINAL').fontSize(9).fontColor(C_FAINT).letterSpacing(2)
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Column({ space: 3 }) {
            Circle({ width: 7, height: 7 })
              .fill(this.vpnRunning ? C_OK : '#3F4C60')
            Text(this.vpnRunning ? 'ONLINE' : 'OFFLINE')
              .fontSize(10).fontColor(this.vpnRunning ? C_OK : C_FAINT).letterSpacing(1)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(8)
          .border({ width: 1, color: this.vpnRunning ? 'rgba(74,222,128,0.5)' : C_LINE2 })
          .backgroundColor('rgba(12,18,25,0.8)')
        }
        .width('100%')
        .padding({ top: px2vp(this.sysBarPx) + 10, left: 16, right: 16 })

        Scroll() {
          Column() {
            // HERO 面板
            Column() {
              Row() {
                Text('TUNNEL').fontSize(10).fontColor(C_FAINT).letterSpacing(1.5)
                Text(this.vpnRunning ? 'CONNECTED' :
                  (this.connectionState === 'error' ? 'ERROR' : 'STANDBY'))
                  .fontSize(10).fontColor(this.vpnRunning ? C_OK : C_CY).letterSpacing(1.5)
              }
              .width('100%')

              Row({ space: 16 }) {
                // 圆环连接按钮
                Stack() {
                  Circle({ width: 96, height: 96 })
                    .fill('none')
                    .stroke(this.vpnRunning ? 'rgba(74,222,128,0.6)' : 'rgba(34,211,238,0.55)')
                    .strokeWidth(2)
                    .strokeDashArray([6, 7])
                  Circle({ width: 80, height: 80 })
                    .fill(this.vpnRunning ? 'rgba(20,83,45,0.85)' : 'rgba(22,78,99,0.85)')
                    .stroke({ color: C_LINE2, width: 1 })
                  Text(this.vpnRunning ? '断开' :
                    (this.connectionState === 'starting' || this.connectionState === 'stopping' ? '等待' : '连接'))
                    .fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.vpnRunning ? C_OK : C_CY)
                    .letterSpacing(1)
                }
                .rotate({ angle: this.ringAngle })
                .onClick(() => { this.toggleVpn(); })

                // 读数
                Column({ space: 6 }) {
                  Row() {
                    Text('NODE ').fontSize(10).fontColor(C_FAINT)
                    Text(this.selectedName()).fontSize(12).fontColor(C_CY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.width('100%')
                  Row() {
                    Text('PING ').fontSize(10).fontColor(C_FAINT)
                    Text(this.selectedMs() >= 0 ? this.selectedMs() + ' ms' : '--').fontSize(12).fontColor(C_CY)
                  }.width('100%')
                  Row() {
                    Text('THROUGHPUT ').fontSize(10).fontColor(C_FAINT)
                    Text(this.downSpeed).fontSize(12).fontColor(C_MG)
                  }.width('100%')
                  Row() {
                    Text('UPTIME ').fontSize(10).fontColor(C_FAINT)
                    Text(this.uptime).fontSize(12).fontColor(C_CY)
                  }.width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .margin({ top: 12 })

              // 示波器
              Stack() {
                Canvas(this.canvasCtx)
                  .width('100%').height(54)
                  .onReady((ctx: CanvasRenderingContext2D) => {
                    this.canvasCtx = ctx;
                    this.drawWave();
                  })
              }
              .width('100%')
              .margin({ top: 12 })
              .borderRadius(12)
              .backgroundColor('#05080D')
              .border({ width: 1, color: C_LINE })
              .opacity(this.vpnRunning ? 1 : 0.35)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .borderRadius(20)
            .border({ width: 1, color: C_LINE })
            .backgroundColor(C_PANEL2)

            // 流量面板（会话真实累计）
            Column() {
              Row() {
                Text('TRAFFIC·SESSION').fontSize(10).fontColor(C_FAINT).letterSpacing(1.5)
                Blank()
                Text('↑ ' + this.upSpeed).fontSize(10).fontColor(C_CY)
                Text('  ↓ ' + this.downSpeed).fontSize(10).fontColor(C_MG)
              }.width('100%')
              Text('↑ ' + this.fmtBytes(this.sessUp) + '   ↓ ' + this.fmtBytes(this.sessDown))
                .fontSize(15).fontColor(C_TXT).margin({ top: 6 })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 11, bottom: 11 })
            .borderRadius(16)
            .border({ width: 1, color: C_LINE })
            .backgroundColor(C_PANEL2)
            .margin({ top: 12 })

            // 操作按钮
            Row({ space: 8 }) {
              Button('添加节点').fontSize(12).height(36).layoutWeight(1)
                .backgroundColor('rgba(12,18,25,0.85)').fontColor('#9FB3C8')
                .border({ width: 1, color: C_LINE })
                .onClick(() => { this.addNew(); })
              Button(this.testRunning ? this.testDone + '/' + this.testTotal : '一键测速')
                .fontSize(12).height(36).layoutWeight(1)
                .backgroundColor(this.testRunning ? 'rgba(34,211,238,0.16)' : 'rgba(12,18,25,0.85)')
                .fontColor(this.testRunning ? C_CY : '#9FB3C8')
                .border({ width: 1, color: this.testRunning ? 'rgba(34,211,238,0.5)' : C_LINE })
                .onClick(() => { this.runSpeedTest(); })
              Button('扫码导入').fontSize(12).height(36).layoutWeight(1)
                .backgroundColor('rgba(12,18,25,0.85)').fontColor('#9FB3C8')
                .border({ width: 1, color: C_LINE })
                .onClick(() => { this.scanImport(); })
              Button('导入链接').fontSize(12).height(36).layoutWeight(1)
                .backgroundColor('rgba(12,18,25,0.85)').fontColor('#9FB3C8')
                .border({ width: 1, color: C_LINE })
                .onClick(() => { this.dialogText = ''; this.dialogController.open(); })
            }
            .width('100%')
            .margin({ top: 12 })

            // 筛选 chips
            Scroll() {
              Row({ space: 7 }) {
                ForEach(this.getGroups(), (g: NodeGroup) => {
                  Text(g.title).fontSize(11).fontColor(this.filter === g.title ? '#A5F3FC' : C_DIM)
                    .padding({ left: 13, right: 13, top: 7, bottom: 7 })
                    .borderRadius(9)
                    .border({ width: 1, color: this.filter === g.title ? 'rgba(34,211,238,0.65)' : C_LINE })
                    .backgroundColor(this.filter === g.title ? 'rgba(34,211,238,0.12)' : 'rgba(12,18,25,0.85)')
                    .onClick(() => { this.filter = g.title; })
                }, (g: NodeGroup) => g.title)
                Text('全部').fontSize(11).fontColor(this.filter === '全部' ? '#A5F3FC' : C_DIM)
                  .padding({ left: 13, right: 13, top: 7, bottom: 7 })
                  .borderRadius(9)
                  .border({ width: 1, color: this.filter === '全部' ? 'rgba(34,211,238,0.65)' : C_LINE })
                  .backgroundColor(this.filter === '全部' ? 'rgba(34,211,238,0.12)' : 'rgba(12,18,25,0.85)')
                  .onClick(() => { this.filter = '全部'; })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .width('100%')
            .margin({ top: 12 })
            .scrollBar(BarState.Off)

            // 列表头
            Row() {
              Text('NODES·').fontSize(11).fontColor('#AEBCD0')
              Text('' + this.profiles.length).fontSize(11).fontColor(C_CY)
              Blank()
              Text('LAST TEST ' + this.lastTestAt).fontSize(10).fontColor(C_FAINT)
            }
            .width('100%')
            .margin({ top: 12, bottom: 6 })

            // 节点列表
            List({ space: 7 }) {
              ForEach(this.getGroups(), (g: NodeGroup) => {
                ListItemGroup({ header: this.groupHeader(g) }) {
                  ForEach(g.items, (p: Profile) => {
                    ListItem() {
                      this.nodeRow(p)
                    }
                  }, (p: Profile) => p.id + '_' + p.testMs)
                }
                .width('100%')
              }, (g: NodeGroup) => g.title + '_' + g.items.length)
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: px2vp(this.navBarPx) + 90 })
        }
        .scrollable(ScrollDirection.Vertical)
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)

        // 底部导航
        Row() {
          Text('节点').fontSize(10).fontColor(C_CY)
            .textAlign(TextAlign.Center).layoutWeight(1)
            .onClick(() => { this.refresh(); })
          Text('订阅').fontSize(10).fontColor(C_FAINT)
            .textAlign(TextAlign.Center).layoutWeight(1)
            .onClick(() => { this.openSubscriptions(); })
          Text('设置').fontSize(10).fontColor(C_FAINT)
            .textAlign(TextAlign.Center).layoutWeight(1)
            .onClick(() => { router.pushUrl({ url: 'pages/Settings' }); })
          Text('日志').fontSize(10).fontColor(C_FAINT)
            .textAlign(TextAlign.Center).layoutWeight(1)
            .onClick(() => { router.pushUrl({ url: 'pages/Logs' }); })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .border({ width: { top: 1 }, color: { top: C_LINE } })
        .backgroundColor('rgba(7,11,16,0.9)')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
