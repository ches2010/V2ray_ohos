import { router } from '@kit.ArkUI';
import { buffer } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { Profile } from '../model/Profile';
import { ProfileStore, XraySettings } from '../core/ProfileStore';
import { LibXray } from '../native/libxray';

/** 日志/诊断页：核心库加载状态、运行状态、最近错误与当前生效配置 */
@Entry
@Component
struct LogsPage {
  @State statusJson: string = '';
  @State diagJson: string = '';
  @State selftestJson: string = '';
  @State coreVersion: string = '';
  @State nodeName: string = '';
  @State routeLabel: string = '';
  @State muxLabel: string = '';
  @State sniffLabel: string = '';
  @State refreshing: boolean = false;
  @StorageProp('vpnRunning') vpnRunning: boolean = false;
  @StorageProp('sysBarHeightPx') sysBarPx: number = 0;
  @StorageProp('navBarHeightPx') navBarPx: number = 0;

  aboutToAppear(): void {
    this.collect();
  }

  async collect(): Promise<void> {
    this.refreshing = true;
    // VPN 进程（VpnExtensionAbility 独立进程）会把阶段状态写入 files/diag.json
    try {
      let ctx = getContext(this) as common.Context;
      let file = fs.openSync(ctx.filesDir + '/diag.json', fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(file.fd);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file.fd);
      this.diagJson = buffer.from(buf).toString('utf-8');
      // 从 VPN 进程诊断里带出的自检结果（selftest 阶段的 detail）
      let d = JSON.parse(this.diagJson) as Record<string, Object>;
      let detail = String(d['detail'] ?? '');
      this.selftestJson = detail.indexOf('inbound:') >= 0 ? detail : '';
    } catch (e) {
      this.diagJson = '';
      this.selftestJson = '';
    }
    // UI 进程视角的核心状态（仅参考）
    try {
      this.statusJson = LibXray.getCoreStatus();
    } catch (e) {
      this.statusJson = '';
    }
    try {
      this.coreVersion = LibXray.checkVersion();
    } catch (e) {
      this.coreVersion = '未知';
    }
    let profiles: Profile[] = await ProfileStore.loadProfiles();
    let id: string = await ProfileStore.loadSelectedId();
    this.nodeName = '未选择节点';
    for (let i = 0; i < profiles.length; i++) {
      if (profiles[i].id === id) {
        this.nodeName = profiles[i].name + '（' + profiles[i].configType.toUpperCase()
          + ' ' + profiles[i].server + ':' + profiles[i].serverPort + '）';
        break;
      }
    }
    let s: XraySettings = await ProfileStore.loadSettings();
    this.routeLabel = s.routeMode === 0 ? '全局代理' : '绕过局域网及大陆';
    this.muxLabel = s.enableMux ? '开启' : '关闭';
    this.sniffLabel = s.enableSniffing ? '开启' : '关闭';
    this.refreshing = false;
  }

  selftestPart(key: string): string {
    if (this.selftestJson === '') {
      return '未运行';
    }
    let idx = this.selftestJson.indexOf(key + ':');
    if (idx < 0) {
      return '未运行';
    }
    let rest = this.selftestJson.substring(idx + key.length + 1);
    let end = rest.indexOf(' ');
    let val = end < 0 ? rest : rest.substring(0, end);
    return val === 'ok' ? '通过' : '失败';
  }

  selftestOk(key: string): string {
    return this.selftestPart(key) === '通过' ? '#22C55E' : '#EF4444';
  }

  diagValue(key: string): string {
    if (this.diagJson === '') {
      return '（VPN 进程尚未写入诊断）';
    }
    try {
      let obj = JSON.parse(this.diagJson) as Record<string, Object>;
      let v = obj[key];
      if (v === undefined || v === null) {
        return '-';
      }
      return String(v);
    } catch (e) {
      return '-';
    }
  }

  statusValue(key: string): string {
    if (this.statusJson === '') {
      return '未知';
    }
    try {
      let obj = JSON.parse(this.statusJson) as Record<string, Object>;
      let v = obj[key];
      if (v === undefined || v === null) {
        return '未知';
      }
      if (typeof v === 'boolean') {
        let b = v as boolean;
        return b ? '正常' : '否';
      }
      let s = String(v);
      return s === '' ? '无' : s;
    } catch (e) {
      return '未知';
    }
  }

  @Builder
  row(label: string, value: string, valueColor: string) {
    Row({ space: 10 }) {
      Text(label).fontSize(14).fontColor('#8A94A8')
      Blank()
      Text(value).fontSize(14).fontColor(valueColor)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Text('←').fontSize(22).fontColor('#E5EDFF')
          .onClick(() => { router.back(); })
        Text('日志诊断').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
        Blank()
        Button(this.refreshing ? '...' : '刷新')
          .fontSize(13).height(32).backgroundColor('#1D2A44')
          .onClick(() => { this.collect(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: px2vp(this.sysBarPx) + 12, bottom: 8 })

      Scroll() {
        Column() {
          Text('核心状态').fontSize(13).fontColor('#94A3B8')
            .width('100%').padding({ left: 4, right: 4, top: 6, bottom: 4 })
          Column({ space: 2 }) {
            this.row('Xray 核心库 (libxray.so)', this.statusValue('xrayLibLoaded'),
              this.statusValue('xrayLibLoaded') === '正常' ? '#22C55E' : '#EF4444')
            this.row('tun2socks 库 (libhevsocks5tun.so)', this.statusValue('hevLibLoaded'),
              this.statusValue('hevLibLoaded') === '正常' ? '#22C55E' : '#EF4444')
            this.row('Xray 已启动', this.statusValue('xrayStarted'),
              this.statusValue('xrayStarted') === '正常' ? '#22C55E' : '#8A94A8')
            this.row('隧道转发中', this.vpnRunning ? '是' : '否',
              this.vpnRunning ? '#22C55E' : '#8A94A8')
            this.row('Geo 资源目录就绪', this.statusValue('assetDirSet'),
              this.statusValue('assetDirSet') === '正常' ? '#22C55E' : '#EAB308')
          }
          .width('100%')
          .borderRadius(10)
          .backgroundColor('#151E31')

          Text('VPN 进程阶段状态').fontSize(13).fontColor('#94A3B8')
            .width('100%').padding({ left: 4, right: 4, top: 14, bottom: 4 })
          Column({ space: 2 }) {
            this.row('阶段', this.diagValue('stage'), '#E5EDFF')
            this.row('结果', this.diagValue('ok') === 'true' ? '成功' : this.diagValue('ok'),
              this.diagValue('ok') === 'true' ? '#22C55E' : '#EF4444')
            this.row('详情', this.diagValue('detail'), '#E5EDFF')
          }
          .width('100%')
          .borderRadius(10)
          .backgroundColor('#151E31')

          Text('全链路自检（经代理连 1.1.1.1:80）').fontSize(13).fontColor('#94A3B8')
            .width('100%').padding({ left: 4, right: 4, top: 14, bottom: 4 })
          Column({ space: 2 }) {
            this.row('SOCKS 入站 (10808)', this.selftestPart('inbound'), this.selftestOk('inbound'))
            this.row('SOCKS5 握手', this.selftestPart('handshake'), this.selftestOk('handshake'))
            this.row('经代理 TCP 连接', this.selftestPart('tcp'), this.selftestOk('tcp'))
            this.row('HTTP 请求', this.selftestPart('http'), this.selftestOk('http'))
          }
          .width('100%')
          .borderRadius(10)
          .backgroundColor('#151E31')

          Text('最近错误').fontSize(13).fontColor('#94A3B8')
            .width('100%').padding({ left: 4, right: 4, top: 14, bottom: 4 })
          Column() {
            Text(this.statusValue('lastError'))
              .fontSize(13).fontColor(this.statusValue('lastError') === '无' ? '#22C55E' : '#F87171')
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('#151E31')

          Text('核心版本').fontSize(13).fontColor('#94A3B8')
            .width('100%').padding({ left: 4, right: 4, top: 14, bottom: 4 })
          Column() {
            Text(this.coreVersion === '' ? '读取中...' : this.coreVersion)
              .fontSize(13).fontColor('#E5EDFF')
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('#151E31')

          Text('当前生效配置').fontSize(13).fontColor('#94A3B8')
            .width('100%').padding({ left: 4, right: 4, top: 14, bottom: 4 })
          Column({ space: 2 }) {
            this.row('选中节点', this.nodeName, '#E5EDFF')
            this.row('路由模式', this.routeLabel, '#E5EDFF')
            this.row('Mux 多路复用', this.muxLabel, '#E5EDFF')
            this.row('流量嗅探', this.sniffLabel, '#E5EDFF')
          }
          .width('100%')
          .borderRadius(10)
          .backgroundColor('#151E31')

          Text('提示：若核心库显示「否」，说明安装包未包含核心库，请使用带 cores 的构建；'
            + '若 Xray 已启动仍无法上网，请检查节点是否可用，并尝试在设置中下载 Geo 数据。')
            .fontSize(11).fontColor('#64748B')
            .width('100%')
            .padding({ left: 4, right: 4, top: 12, bottom: px2vp(this.navBarPx) + 24 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B1220')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
