import { router, promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProfileStore, SubscriptionInfo } from '../core/ProfileStore';

/** 订阅分组管理：添加 / 刷新 / 删除订阅，节点按订阅分组归档 */
@Entry
@Component
struct SubscriptionPage {
  @State subs: SubscriptionInfo[] = [];
  @State showAdd: boolean = false;
  @State newName: string = '';
  @State newUrl: string = '';
  @State busyKey: string = '';

  aboutToAppear(): void {
    this.refresh();
  }

  refresh(): void {
    ProfileStore.loadSubscriptions().then((s: SubscriptionInfo[]) => {
      this.subs = s;
    });
  }

  add(): void {
    if (this.busyKey !== '') {
      return;
    }
    let url = this.newUrl.trim();
    if (url === '') {
      promptAction.showToast({ message: '请输入订阅地址' });
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      promptAction.showToast({ message: '订阅地址需以 http(s):// 开头' });
      return;
    }
    let name = this.newName.trim();
    if (name === '') {
      name = '订阅 ' + (this.subs.length + 1);
    }
    this.busyKey = 'add';
    this.fetchInto(name, url, '', true);
  }

  refreshSub(s: SubscriptionInfo): void {
    if (this.busyKey !== '') {
      return;
    }
    this.busyKey = s.id;
    this.fetchInto(s.name, s.url, s.id, false);
  }

  private fetchInto(name: string, url: string, subId: string, isNew: boolean): void {
    let req = http.createHttp();
    req.request(url, { method: http.RequestMethod.GET, connectTimeout: 15000, readTimeout: 20000 })
      .then((res: http.HttpResponse) => {
        let body = String(res.result);
        if (isNew) {
          return ProfileStore.addSubscription(name, url, body);
        }
        return ProfileStore.refreshSubscription(subId, body);
      })
      .then((n: number) => {
        if (n < 0) {
          promptAction.showToast({ message: '订阅不存在' });
        } else {
          promptAction.showToast({ message: (isNew ? '添加成功，导入 ' : '已更新，') + n + ' 个节点' });
        }
        this.busyKey = '';
        this.showAdd = false;
        this.newName = '';
        this.newUrl = '';
        this.refresh();
      })
      .catch((e: BusinessError) => {
        promptAction.showToast({ message: '订阅下载/解析失败' });
        this.busyKey = '';
      });
  }

  remove(s: SubscriptionInfo): void {
    ProfileStore.deleteSubscription(s.id).then(() => {
      promptAction.showToast({ message: '已删除订阅及其节点' });
      this.refresh();
    });
  }

  fmtTime(t: number): string {
    if (t <= 0) {
      return '未更新';
    }
    let d = new Date(t);
    let mm = d.getMonth() + 1;
    let dd = d.getDate();
    let hh = d.getHours();
    let mi = d.getMinutes();
    let pad = (x: number): string => {
      return x < 10 ? '0' + x : '' + x;
    };
    return mm + '-' + pad(dd) + ' ' + pad(hh) + ':' + pad(mi);
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 12 }) {
        Text('←').fontSize(22).fontColor('#E5EDFF')
          .onClick(() => { router.back(); })
        Text('订阅管理').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
        Blank()
        Button(this.busyKey === 'add' ? '添加中...' : '+ 添加订阅')
          .fontSize(13).height(32).backgroundColor('#1D2A44')
          .onClick(() => { this.showAdd = !this.showAdd; })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Text('订阅按分组管理：刷新会整体替换该组节点；删除会同时移除该组全部节点')
        .fontSize(11).fontColor('#64748B')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

      if (this.showAdd) {
        Column({ space: 10 }) {
          TextInput({ text: this.newName, placeholder: '订阅名称（可选，如：机场A）' })
            .type(InputType.Normal).height(44).width('100%')
            .onChange((v: string) => { this.newName = v; })
          TextInput({ text: this.newUrl, placeholder: '订阅链接 https://...' })
            .type(InputType.Normal).height(44).width('100%')
            .onChange((v: string) => { this.newUrl = v; })
          Button('下载并导入').width('100%').height(40).backgroundColor('#3B82F6')
            .onClick(() => { this.add(); })
        }
        .width('100%')
        .padding(12)
        .margin({ left: 16, right: 16 })
        .backgroundColor('#151E31')
        .borderRadius(10)
      }

      List({ space: 10 }) {
        ForEach(this.subs, (s: SubscriptionInfo) => {
          ListItem() {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text(s.name)
                  .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#E5EDFF')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(s.count + ' 个节点')
                  .fontSize(11).fontColor('#8A94A8')
              }
              .width('100%')

              Text(s.url)
                .fontSize(11).fontColor('#64748B')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')

              Row({ space: 10 }) {
                Text('更新于 ' + this.fmtTime(s.lastUpdated))
                  .fontSize(11).fontColor('#64748B')
                  .layoutWeight(1)
                if (this.busyKey === s.id) {
                  Text('刷新中...').fontSize(12).fontColor('#94A3B8')
                } else {
                  Text('刷新').fontSize(12).fontColor('#3B82F6')
                    .onClick(() => { this.refreshSub(s); })
                }
                Text('删除').fontSize(12).fontColor('#EF4444')
                  .onClick(() => { this.remove(s); })
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .borderRadius(10)
            .backgroundColor('#151E31')
          }
        }, (s: SubscriptionInfo) => s.id + '_' + s.count + '_' + s.lastUpdated)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .scrollBar(BarState.Off)

      if (this.subs.length === 0) {
        Column() {
          Text('暂无订阅').fontSize(14).fontColor('#64748B')
          Text('点击右上角「+ 添加订阅」，填入订阅链接即可按分组导入节点')
            .fontSize(11).fontColor('#475569').margin({ top: 6 })
        }
        .width('100%')
        .padding(24)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B1220')
  }
}
