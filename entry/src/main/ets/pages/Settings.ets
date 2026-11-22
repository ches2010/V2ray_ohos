import { promptAction, router } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import { ProfileStore, XraySettings } from '../core/ProfileStore';

const LOG_LEVELS: string[] = ['debug', 'info', 'warning', 'error'];
const LOG_LABELS: string[] = ['debug（最详细）', 'info', 'warning（推荐）', 'error（最简）'];

/** 设置页（对应 v2rayNG SettingsActivity：路由分流 / Mux / 嗅探 / 日志 / Geo 数据） */
@Entry
@Component
struct SettingsPage {
  @State routeMode: number = 1;
  @State blockAds: boolean = false;
  @State enableMux: boolean = false;
  @State enableSniffing: boolean = true;
  @State logIndex: number = 2;
  @State geoIpExists: boolean = false;
  @State geoSiteExists: boolean = false;
  @State downloading: string = '';
  @StorageProp('sysBarHeightPx') sysBarPx: number = 0;
  @StorageProp('navBarHeightPx') navBarPx: number = 0;

  aboutToAppear(): void {
    ProfileStore.loadSettings().then((s: XraySettings) => {
      this.routeMode = s.routeMode;
      this.blockAds = s.blockAds;
      this.enableMux = s.enableMux;
      this.enableSniffing = s.enableSniffing;
      let li = LOG_LEVELS.indexOf(s.logLevel);
      this.logIndex = li >= 0 ? li : 2;
    });
    this.checkGeo();
  }

  private assetsDir(): string {
    let ctx = getContext(this);
    return ctx.filesDir + '/assets';
  }

  private checkGeo(): void {
    try {
      this.geoIpExists = fs.accessSync(this.assetsDir() + '/geoip.dat');
      this.geoSiteExists = fs.accessSync(this.assetsDir() + '/geosite.dat');
    } catch (e) {
      this.geoIpExists = false;
      this.geoSiteExists = false;
    }
  }

  private persist(): void {
    let s = new XraySettings();
    s.routeMode = this.routeMode;
    s.blockAds = this.blockAds;
    s.enableMux = this.enableMux;
    s.enableSniffing = this.enableSniffing;
    s.logLevel = LOG_LEVELS[this.logIndex];
    ProfileStore.saveSettings(s);
  }

  /** 下载 geoip/geosite.dat 到应用沙箱 assets（VpnTunnelAbility 启动核心时引用该目录） */
  downloadGeo(name: string): void {
    if (this.downloading !== '') {
      return;
    }
    let url: string = name === 'geoip.dat'
      ? 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat'
      : 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat';
    this.downloading = name;
    let req = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 20000,
      readTimeout: 180000
    }).then((res: http.HttpResponse) => {
      let buf = res.result as ArrayBuffer;
      let dir = this.assetsDir();
      try {
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir, true);
        }
      } catch (e) {
        fs.mkdirSync(dir, true);
      }
      let file = fs.openSync(dir + '/' + name,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, buf);
      fs.closeSync(file.fd);
      promptAction.showToast({ message: name + ' 下载完成（' + Math.round(buf.byteLength / 1024) + ' KB）' });
      this.downloading = '';
      this.checkGeo();
    }).catch((e: BusinessError) => {
      promptAction.showToast({ message: name + ' 下载失败（可能需要可用网络）' });
      this.downloading = '';
    });
  }

  @Builder
  sectionTitle(title: string) {
    Text(title).fontSize(13).fontColor('#94A3B8')
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 4 })
  }

  @Builder
  settingRow(label: string, desc: string, on: boolean, onChange: (v: boolean) => void) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(label).fontSize(15).fontColor('#E5EDFF')
        Text(desc).fontSize(11).fontColor('#8A94A8')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor('#3B82F6')
        .onChange((v: boolean) => { onChange(v); })
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor('#151E31')
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 12 }) {
        Text('←').fontSize(22).fontColor('#E5EDFF')
          .onClick(() => { router.back(); })
        Text('设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: px2vp(this.sysBarPx) + 12, bottom: 4 })

      Scroll() {
        Column() {
          this.sectionTitle('路由分流')

          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text('路由模式').fontSize(15).fontColor('#E5EDFF')
                Text(this.routeMode === 0 ? '全局代理：所有流量走代理' : '绕过局域网及大陆：国内直连')
                  .fontSize(11).fontColor('#8A94A8')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Select([
                { value: '全局代理' },
                { value: '绕过局域网及大陆' }
              ])
                .selected(this.routeMode)
                .value(this.routeMode === 0 ? '全局代理' : '绕过局域网及大陆')
                .font({ size: 13 })
                .fontColor('#E5EDFF')
                .selectedOptionFont({ size: 13 })
                .optionFont({ size: 13 })
                .onSelect((index: number) => {
                  this.routeMode = index;
                  this.persist();
                })
            }
            .width('100%')

            this.settingRow('拦截广告', '命中广告域名列表的请求直接阻断（依赖 geosite 数据）',
              this.blockAds, (v: boolean) => {
                this.blockAds = v;
                this.persist();
              })
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('rgba(21,30,49,0.5)')

          this.sectionTitle('核心')

          Column({ space: 10 }) {
            this.settingRow('Mux 多路复用', '减少握手开销，弱网下更流畅（vless/vmess/trojan）',
              this.enableMux, (v: boolean) => {
                this.enableMux = v;
                this.persist();
              })
            this.settingRow('流量嗅探 sniffing', '嗅探 TLS/HTTP 域名，域名分流规则依赖此项',
              this.enableSniffing, (v: boolean) => {
                this.enableSniffing = v;
                this.persist();
              })
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text('日志级别').fontSize(15).fontColor('#E5EDFF')
                Text('排查问题时调高详细度').fontSize(11).fontColor('#8A94A8')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Select([
                { value: LOG_LABELS[0] },
                { value: LOG_LABELS[1] },
                { value: LOG_LABELS[2] },
                { value: LOG_LABELS[3] }
              ])
                .selected(this.logIndex)
                .value(LOG_LABELS[this.logIndex])
                .font({ size: 13 })
                .fontColor('#E5EDFF')
                .onSelect((index: number) => {
                  this.logIndex = index;
                  this.persist();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('rgba(21,30,49,0.5)')

          this.sectionTitle('Geo 数据（路由分流依赖）')

          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text('geoip.dat').fontSize(15).fontColor('#E5EDFF')
                Text(this.geoIpExists ? '已就绪' : '未下载（绕过大陆/广告拦截需要）')
                  .fontSize(11).fontColor(this.geoIpExists ? '#22C55E' : '#EAB308')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Button(this.downloading === 'geoip.dat' ? '下载中...' : (this.geoIpExists ? '重新下载' : '下载'))
                .fontSize(12).height(30).backgroundColor('#1D2A44')
                .onClick(() => { this.downloadGeo('geoip.dat'); })
            }
            .width('100%')

            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text('geosite.dat').fontSize(15).fontColor('#E5EDFF')
                Text(this.geoSiteExists ? '已就绪' : '未下载（绕过大陆/广告拦截需要）')
                  .fontSize(11).fontColor(this.geoSiteExists ? '#22C55E' : '#EAB308')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Button(this.downloading === 'geosite.dat' ? '下载中...' : (this.geoSiteExists ? '重新下载' : '下载'))
                .fontSize(12).height(30).backgroundColor('#1D2A44')
                .onClick(() => { this.downloadGeo('geosite.dat'); })
            }
            .width('100%')

            Text('数据源：Loyalsoldier/v2ray-rules-dat，保存到应用沙箱 files/assets，重启 VPN 后生效')
              .fontSize(10).fontColor('#64748B')
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('rgba(21,30,49,0.5)')

          this.sectionTitle('更多')

          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text('日志诊断').fontSize(15).fontColor('#E5EDFF')
                Text('核心库加载状态、最近错误与生效配置').fontSize(11).fontColor('#8A94A8')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('查看 →').fontSize(13).fontColor('#3B82F6')
                .onClick(() => { router.pushUrl({ url: 'pages/Logs' }); })
            }
            .width('100%')

            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text('关于与检查更新').fontSize(15).fontColor('#E5EDFF')
                Text('版本信息、上游项目、新版本检测').fontSize(11).fontColor('#8A94A8')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('查看 →').fontSize(13).fontColor('#3B82F6')
                .onClick(() => { router.pushUrl({ url: 'pages/About' }); })
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('rgba(21,30,49,0.5)')

          Text('设置即时保存；下次启动 VPN 隧道时生效')
            .fontSize(11).fontColor('#64748B')
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: px2vp(this.navBarPx) + 16 })
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
