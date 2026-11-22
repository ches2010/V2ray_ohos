import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { Profile } from '../model/Profile';
import { ProfileStore } from '../core/ProfileStore';
import { ConfigBuilder } from '../core/ConfigBuilder';
import { VpnController } from '../core/VpnController';
import { LibXray } from '../native/libxray';

@CustomDialog
struct ImportDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: '' });
  @Link inputText: string;
  @Link importMode: number; // 0 = 分享链接, 1 = 订阅
  onConfirm: (text: string, mode: number) => void = (t: string, m: number) => {};

  build() {
    Column({ space: 12 }) {
      Text(this.importMode === 0 ? '导入分享链接' : '导入订阅')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
      TextInput({ text: this.inputText, placeholder: this.importMode === 0 ? 'vless://... / vmess://... / ss://...' : '订阅地址内容(base64或明文链接列表)' })
        .type(InputType.DEFAULT)
        .height(this.importMode === 0 ? 48 : 120)
        .width('100%')
        .onChange((v: string) => { this.inputText = v; })
      Row({ space: 12 }) {
        Button('取消').onClick(() => { this.controller.close(); }).layoutWeight(1)
        Button('导入').onClick(() => { this.controller.close(); this.onConfirm(this.inputText, this.importMode); }).layoutWeight(1)
      }.width('100%')
    }
    .padding(16)
    .width('90%')
    .backgroundColor('#151E31')
    .borderRadius(12)
  }
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
  @State importMode: number = 0;
  dialogController: CustomDialogController = new CustomDialogController({
    builder: ImportDialog({
      inputText: $dialogText,
      importMode: $importMode,
      onConfirm: (t: string, m: number) => { this.doImport(t, m); }
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

  doImport(text: string, mode: number): void {
    let t = text.trim();
    if (t === '') {
      return;
    }
    if (mode === 0) {
      ProfileStore.addShareLink(t).then((p: Profile | null) => {
        if (p === null) {
          promptAction.showToast({ message: '链接解析失败' });
        } else {
          promptAction.showToast({ message: '已添加: ' + p.name });
          this.refresh();
        }
      });
    } else {
      // 订阅地址内容：尝试先下载再解析
      this.fetchSubscription(t);
    }
  }

  fetchSubscription(urlOrContent: string): void {
    let isUrl = urlOrContent.startsWith('http://') || urlOrContent.startsWith('https://');
    if (!isUrl) {
      ProfileStore.importSubscription(urlOrContent).then((n: number) => {
        promptAction.showToast({ message: '导入 ' + n + ' 个节点' });
        this.refresh();
      });
      return;
    }
    import { http } from '@kit.NetworkKit';
    let req = http.createHttp();
    req.request(urlOrContent, { method: http.RequestMethod.GET, connectTimeout: 15000, readTimeout: 20000 })
      .then((res: http.HttpResponse) => {
        let body = String(res.result);
        return ProfileStore.importSubscription(body);
      })
      .then((n: number) => {
        promptAction.showToast({ message: '订阅导入 ' + n + ' 个节点' });
        this.refresh();
      })
      .catch((e: Object) => {
        promptAction.showToast({ message: '订阅下载失败' });
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

  testLatency(): void {
    let target: Profile | null = null;
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id === this.selectedId) {
        target = this.profiles[i];
        break;
      }
    }
    if (target === null) {
      promptAction.showToast({ message: '未选择节点' });
      return;
    }
    let cfg = ConfigBuilder.buildXrayConfig(target);
    let ms = LibXray.measureOutboundDelay(cfg, 'https://www.gstatic.com/generate_204');
    this.latency = ms;
    promptAction.showToast({ message: ms >= 0 ? ('延迟 ' + ms + ' ms') : '测速失败' });
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

      // 操作栏
      Row({ space: 10 }) {
        Button('添加节点').fontSize(13).height(34).backgroundColor('#1D2A44').onClick(() => { this.addNew(); })
        Button('测速').fontSize(13).height(34).backgroundColor('#1D2A44').onClick(() => { this.testLatency(); })
        Button('导入链接').fontSize(13).height(34).backgroundColor('#1D2A44')
          .onClick(() => { this.importMode = 0; this.dialogText = ''; this.dialogController.open(); })
        Button('导入订阅').fontSize(13).height(34).backgroundColor('#1D2A44')
          .onClick(() => { this.importMode = 1; this.dialogText = ''; this.dialogController.open(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 6 })

      // 节点列表
      List({ space: 8 }) {
        ForEach(this.profiles, (p: Profile) => {
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
        }, (p: Profile) => p.id)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B1220')
  }
}
