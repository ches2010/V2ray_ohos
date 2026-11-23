import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, bundleManager, Want } from '@kit.AbilityKit';
import { isNewerVersion } from '../core/UpdateVersion';

const RELEASE_API = 'https://api.github.com/repos/ches2010/V2ray_ohos/releases/latest';
const RELEASE_PAGE = 'https://github.com/ches2010/V2ray_ohos/releases/latest';
const UPSTREAM = 'https://github.com/2dust/v2rayNG';

/** 关于页：应用信息、检查更新、上游项目与许可 */
@Entry
@Component
struct AboutPage {
  @State versionName: string = '';
  @State checking: boolean = false;
  @State checkResult: string = '';
  @State latestTag: string = '';
  @State hasUpdate: boolean = false;
  @StorageProp('sysBarHeightPx') sysBarPx: number = 0;
  @StorageProp('navBarHeightPx') navBarPx: number = 0;

  aboutToAppear(): void {
    try {
      let info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (e) {
      this.versionName = '';
    }
  }

  /** 检查更新：对比 GitHub latest release 与当前版本 */
  checkUpdate(): void {
    if (this.checking) {
      return;
    }
    this.checking = true;
    this.checkResult = '';
    let req = http.createHttp();
    req.request(RELEASE_API, {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': 'v2rayng-port' },
      connectTimeout: 15000,
      readTimeout: 15000
    }).then((res: http.HttpResponse) => {
      if (res.responseCode !== 200) {
        this.hasUpdate = false;
        this.checkResult = '检查失败（HTTP ' + res.responseCode + '）';
        this.checking = false;
        return;
      }
      let obj = JSON.parse(String(res.result)) as Record<string, Object>;
      let tag = String(obj['tag_name'] ?? '');
      this.latestTag = tag;
      let latest = tag.replace(/^v/, '');
      if (latest !== '' && isNewerVersion(this.versionName, latest)) {
        this.hasUpdate = true;
        this.checkResult = '发现新版本 ' + tag + '（当前 ' + this.versionName + '），可前往 Release 页下载。';
      } else {
        this.hasUpdate = false;
        this.checkResult = '当前已是最新版本（' + this.versionName + '）。';
      }
      this.checking = false;
    }).catch((e: BusinessError) => {
      this.checkResult = '检查失败（网络不可用或受限）：' + e.code;
      this.checking = false;
    });
  }

  openUrl(url: string): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    let want: Want = { action: 'ohos.want.action.viewData', uri: url };
    ctx.startAbility(want).catch(() => {
      promptAction.showToast({ message: '打开浏览器失败' });
    });
  }

  @Builder
  linkRow(label: string, desc: string, url: string) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(label).fontSize(15).fontColor('#E5EDFF')
        Text(desc).fontSize(11).fontColor('#8A94A8')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('前往 ↗').fontSize(13).fontColor('#3B82F6')
        .onClick(() => { this.openUrl(url); })
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor('#151E31')
    .onClick(() => { this.openUrl(url); })
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Text('←').fontSize(22).fontColor('#E5EDFF')
          .onClick(() => { router.back(); })
        Text('关于').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: px2vp(this.sysBarPx) + 12, bottom: 8 })

      Scroll() {
        Column() {
          // 应用标识
          Column({ space: 6 }) {
            Text('V2ray').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
            Text(this.versionName === '' ? '版本信息读取中...' : '版本 ' + this.versionName)
              .fontSize(13).fontColor('#8A94A8')
            Text('V2RayNG 的 HarmonyOS NEXT 移植版：ArkTS + ArkUI 界面，Xray 核心（ohos-go 交叉编译）+ hev-socks5-tunnel，经 NAPI dlopen 接入。')
              .fontSize(12).fontColor('#8A94A8')
              .textAlign(TextAlign.Center)
              .padding({ top: 6 })
          }
          .width('100%')
          .padding(18)
          .borderRadius(12)
          .backgroundColor('#151E31')

          // 检查更新
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text('检查更新').fontSize(15).fontColor('#E5EDFF')
                Text('对比 GitHub Releases 的最新版本').fontSize(11).fontColor('#8A94A8')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Button(this.checking ? '检查中...' : '检查')
                .fontSize(12).height(30).backgroundColor('#1D2A44')
                .onClick(() => { this.checkUpdate(); })
            }
            .width('100%')

            if (this.checkResult !== '') {
              Text(this.checkResult)
                .fontSize(12)
                .fontColor(this.hasUpdate ? '#EAB308' : '#22C55E')
                .width('100%')
              if (this.hasUpdate) {
                Button('前往下载 ' + this.latestTag)
                  .fontSize(13).height(36).width('100%').backgroundColor('#3B82F6')
                  .onClick(() => { this.openUrl(RELEASE_PAGE); })
              }
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('#151E31')

          // 相关链接
          Column({ space: 10 }) {
            this.linkRow('上游项目 v2rayNG', '本移植的 Android 原版（GPL-3.0）', UPSTREAM)
            this.linkRow('本项目 Releases', '获取最新 HAP 与核心库', RELEASE_PAGE)
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('rgba(21,30,49,0.5)')

          // 许可与免责
          Column({ space: 6 }) {
            Text('开源许可').fontSize(13).fontColor('#94A3B8').width('100%')
            Text('本项目遵循 GPL-3.0 协议开源；Xray-core 为 MIT 协议，hev-socks5-tunnel 为 MIT 协议。')
              .fontSize(12).fontColor('#8A94A8').width('100%')
            Text('免责声明').fontSize(13).fontColor('#94A3B8').width('100%').padding({ top: 6 })
            Text('本应用仅用于网络技术学习和个人合规使用，请遵守所在地区法律法规；使用本应用产生的一切后果由使用者自行承担。')
              .fontSize(12).fontColor('#8A94A8').width('100%')
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('rgba(21,30,49,0.5)')

          Text('V2ray · ' + (this.versionName === '' ? 'HarmonyOS NEXT' : 'v' + this.versionName))
            .fontSize(10).fontColor('#475569')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 10, bottom: px2vp(this.navBarPx) + 24 })
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
