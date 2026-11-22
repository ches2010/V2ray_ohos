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

@CustomDialog
struct LinkDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: '' });
  @Link inputText: string;
  onConfirm: (text: string) => void = (t: string) => {};

  build() {
    Column({ space: 12 }) {
      Text('导入分享链接')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
      TextInput({ text: this.inputText, placeholder: 'vless://... / vmess://... / ss://...' })
        .type(InputType.Normal)
        .height(48)
        .width('100%')
        .onChange((v: string) => { this.inputText = v; })
      Row({ space: 12 }) {
        Button('取消').onClick(() => { this.controller.close(); }).layoutWeight(1)
        Button('导入').onClick(() => { this.controller.close(); this.onConfirm(this.inputText); }).layoutWeight(1)
      }.width('100%')
    }
    .padding(16)
    .width('90%')
    .backgroundColor('#151E31')
    .borderRadius(12)
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
      Text('分享节点').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
      if (this.qrPixmap !== null) {
        Image(this.qrPixmap as image.PixelMap).width(240).height(240).borderRadius(8)
      } else {
        Text('二维码生成中...').fontSize(13).fontColor('#8A94A8').height(240)
      }
      Text(this.linkText)
        .fontSize(11).fontColor('#8A94A8')
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 12 }) {
        Button('复制链接').onClick(() => { this.copyLink(); }).layoutWeight(1)
        Button('关闭').onClick(() => { this.controller.close(); }).layoutWeight(1)
      }.width('100%')
    }
    .padding(16)
    .width('90%')
    .backgroundColor('#151E31')
    .borderRadius(12)
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
  @StorageProp('vpnRunning') @Watch('onRunningChanged') vpnRunning: boolean = false;
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
  dialogController: CustomDialogController = new CustomDialogController({
    builder: LinkDialog({
      inputText: $dialogText,
      onConfirm: (t: string) => { this.doImportLink(t); }
    }),
    customStyle: false
  });
  shareDialogController: CustomDialogController = new CustomDialogController({
    builder: ShareDialog({
      linkText: $shareLink,
      qrPixmap: $qrPixmap
    }),
    customStyle: false
  });

  onRunningChanged(): void {
    if (!this.vpnRunning) {
      this.latency = -1;
    }
  }

  aboutToAppear(): void {
    this.refresh();
  }

  refresh(): void {
    ProfileStore.loadProfiles().then((list: Profile[]) => {
      this.profiles = list;
    });
    ProfileStore.loadSelectedId().then((id: string) => {
      this.selectedId = id;
    });
  }

  doImportLink(text: string): void {
    let t = text.trim();
    if (t === '') {
      return;
    }
    ProfileStore.addShareLink(t).then((p: Profile | null) => {
      if (p === null) {
        promptAction.showToast({ message: '链接解析失败' });
      } else {
        promptAction.showToast({ message: '已添加: ' + p.name });
        this.refresh();
      }
    });
  }


  /** 扫码导入节点（鸿蒙统一扫码 ScanKit，替代 v2rayNG 的 ZXing 扫码） */
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
      // 二维码生成失败时仍展示链接
      this.shareDialogController.open();
    });
  }

  toggleVpn(): void {
    if (this.busy) {
      return;
    }
    if (this.selectedId === '') {
      promptAction.showToast({ message: '请先选择一个节点' });
      return;
    }
    this.busy = true;
    if (this.vpnRunning) {
      VpnController.stop().then(() => {
        this.busy = false;
      }).catch(() => {
        this.busy = false;
      });
    } else {
      VpnController.start().then(() => {
        this.busy = false;
        promptAction.showToast({ message: 'VPN 已启动（首次使用需在系统弹窗中授权）' });
      }).catch(() => {
        this.busy = false;
      });
    }
  }

  /** 一键测速：并发对全部节点做 TCP 握手，结果显示在节点卡片上 */
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
      p.testMs = -1;
      cleared.push(p);
    }
    this.profiles = cleared;
    SpeedTest.testAll(this.profiles, 4, 5000, (r: TestResult) => {
      this.applyResult(r);
    }).then(() => {
      this.testRunning = false;
      promptAction.showToast({ message: '测速完成' });
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
    if (ms === -1 || ms === 0) {
      return '';
    }
    if (ms < 0) {
      return '超时';
    }
    return ms + 'ms';
  }

  msColor(ms: number): string {
    if (ms < 0) {
      return '#EF4444';
    }
    if (ms < 300) {
      return '#22C55E';
    }
    if (ms < 800) {
      return '#EAB308';
    }
    return '#F97316';
  }

  /** 按订阅分组：订阅组在前，手动添加的节点归入"手动添加"组放在最后 */
  getGroups(): NodeGroup[] {
    let groups: NodeGroup[] = [];
    let manual = new NodeGroup();
    manual.title = '手动添加';
    for (let i = 0; i < this.profiles.length; i++) {
      let p = this.profiles[i];
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

  @Builder
  groupHeader(g: NodeGroup) {
    Row({ space: 8 }) {
      Text(g.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#94A3B8')
      Text(g.items.length + ' 个节点').fontSize(11).fontColor('#64748B')
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 8, bottom: 2 })
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('V2RayNG').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
        Blank()
        Text(this.vpnRunning ? '已连接' : '未连接')
          .fontSize(13)
          .fontColor(this.vpnRunning ? '#22C55E' : '#8A94A8')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(10)
          .backgroundColor(this.vpnRunning ? 'rgba(34,197,94,0.15)' : 'rgba(138,148,168,0.15)')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 连接按钮
      Column() {
        Button(this.busy ? '切换中...' : (this.vpnRunning ? '断开连接' : '连接'))
          .width(140).height(48)
          .fontSize(17)
          .type(ButtonType.Circle)
          .backgroundColor(this.vpnRunning ? '#7F1D1D' : '#3B82F6')
          .onClick(() => { this.toggleVpn(); })
        Text(this.vpnRunning ? (this.latency >= 0 ? '延迟 ' + this.latency + ' ms' : '隧道运行中') : '点击连接选中的节点')
          .fontSize(12).fontColor('#8A94A8').margin({ top: 8 })
      }
      .width('100%')
      .padding({ top: 8, bottom: 12 })

      // 操作栏（横向可滚动，避免小屏挤压）
      Scroll() {
        Row({ space: 10 }) {
          Button('添加节点').fontSize(13).height(34).backgroundColor('#1D2A44')
            .onClick(() => { this.addNew(); })
          Button(this.testRunning ? ('测速中 ' + this.testDone + '/' + this.testTotal) : '一键测速')
            .fontSize(13).height(34)
            .backgroundColor(this.testRunning ? '#334155' : '#1D2A44')
            .onClick(() => { this.runSpeedTest(); })
          Button('扫码导入').fontSize(13).height(34).backgroundColor('#1D2A44')
            .onClick(() => { this.scanImport(); })
          Button('导入链接').fontSize(13).height(34).backgroundColor('#1D2A44')
            .onClick(() => { this.dialogText = ''; this.dialogController.open(); })
          Button('订阅管理').fontSize(13).height(34).backgroundColor('#1D2A44')
            .onClick(() => { this.openSubscriptions(); })
          Button('设置').fontSize(13).height(34).backgroundColor('#1D2A44')
            .onClick(() => { router.pushUrl({ url: 'pages/Settings' }); })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 6 })

      // 节点列表（按订阅分组）
      List({ space: 8 }) {
        ForEach(this.getGroups(), (g: NodeGroup) => {
          ListItemGroup({ header: this.groupHeader(g) }) {
            ForEach(g.items, (p: Profile) => {
              ListItem() {
                Row({ space: 10 }) {
                  Circle({ width: 10, height: 10 })
                    .fill(p.id === this.selectedId ? '#22C55E' : '#334155')
                  Column({ space: 3 }) {
                    Text(p.name === '' ? p.server : p.name)
                      .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#E5EDFF')
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(p.configType.toUpperCase() + ' · ' + p.server + ':' + p.serverPort)
                      .fontSize(11).fontColor('#8A94A8')
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (this.msLabel(p.testMs) !== '') {
                    Text(this.msLabel(p.testMs))
                      .fontSize(11).fontColor(this.msColor(p.testMs))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(6)
                      .backgroundColor('rgba(148,163,184,0.12)')
                  }
                  Text('分享').fontSize(12).fontColor('#A78BFA')
                    .onClick(() => { this.shareNode(p); })
                  Text('编辑').fontSize(12).fontColor('#3B82F6')
                    .onClick(() => { this.editProfile(p); })
                  Text('删除').fontSize(12).fontColor('#EF4444')
                    .onClick(() => { this.removeProfile(p); })
                }
                .width('100%')
                .padding(12)
                .borderRadius(10)
                .backgroundColor(p.id === this.selectedId ? 'rgba(59,130,246,0.12)' : '#151E31')
                .onClick(() => { this.selectProfile(p.id); })
              }
            }, (p: Profile) => p.id + '_' + p.testMs)
          }
          .width('100%')
        }, (g: NodeGroup) => g.title + '_' + g.items.length)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B1220')
  }
}
