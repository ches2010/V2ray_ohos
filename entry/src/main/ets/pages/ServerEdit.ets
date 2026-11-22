import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { Profile, SUPPORTED_TYPES } from '../model/Profile';
import { ProfileStore } from '../core/ProfileStore';

const TYPE_LABELS: string[] = ['vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'http'];
const NETWORKS: string[] = ['tcp', 'ws', 'grpc'];
const TLS_MODES: string[] = ['', 'tls', 'reality'];
const TLS_LABELS: string[] = ['无', 'TLS', 'Reality'];

@Entry
@Component
struct ServerEdit {
  @State editingId: string = '';
  @State name: string = '';
  @State typeIndex: number = 0;
  @State server: string = '';
  @State serverPort: string = '443';
  @State uuid: string = '';
  @State password: string = '';
  @State security: string = 'aes-256-gcm';
  @State alterId: string = '0';
  @State flow: string = '';
  @State networkIndex: number = 0;
  @State host: string = '';
  @State path: string = '';
  @State serviceName: string = '';
  @State tlsIndex: number = 1;
  @State sni: string = '';
  @State fingerprint: string = 'chrome';
  @State publicKey: string = '';
  @State shortId: string = '';
  @State spiderX: string = '';
  @State allowInsecure: boolean = false;

  aboutToAppear(): void {
    let params: Object | undefined = router.getParams();
    if (params !== undefined && params !== null) {
      let p: Profile = params as Profile;
      if (p.id !== undefined && p.id !== '') {
        this.editingId = p.id;
        this.name = p.name;
        let ti = SUPPORTED_TYPES.indexOf(p.configType);
        this.typeIndex = ti >= 0 ? ti : 0;
        this.server = p.server;
        this.serverPort = String(p.serverPort);
        this.uuid = p.uuid;
        this.password = p.password;
        this.security = p.security === '' ? 'aes-256-gcm' : p.security;
        this.alterId = String(p.alterId);
        this.flow = p.flow;
        let ni = NETWORKS.indexOf(p.network);
        this.networkIndex = ni >= 0 ? ni : 0;
        this.host = p.host;
        this.path = p.path;
        this.serviceName = p.serviceName;
        let li = TLS_MODES.indexOf(p.tls);
        this.tlsIndex = li >= 0 ? li : 0;
        this.sni = p.sni;
        this.fingerprint = p.fingerprint === '' ? 'chrome' : p.fingerprint;
        this.publicKey = p.publicKey;
        this.shortId = p.shortId;
        this.spiderX = p.spiderX;
        this.allowInsecure = p.allowInsecure;
      }
    }
  }

  collect(): Profile {
    let p = new Profile();
    p.id = this.editingId;
    p.name = this.name;
    p.configType = TYPE_LABELS[this.typeIndex];
    p.server = this.server.trim();
    p.serverPort = Number(this.serverPort === '' ? '443' : this.serverPort);
    p.uuid = this.uuid.trim();
    p.password = this.password;
    p.security = this.security;
    p.alterId = Number(this.alterId === '' ? '0' : this.alterId);
    p.flow = this.flow.trim();
    p.network = NETWORKS[this.networkIndex];
    p.host = this.host.trim();
    p.path = this.path.trim();
    p.serviceName = this.serviceName.trim();
    p.tls = TLS_MODES[this.tlsIndex];
    p.sni = this.sni.trim();
    p.fingerprint = this.fingerprint.trim();
    p.publicKey = this.publicKey.trim();
    p.shortId = this.shortId.trim();
    p.spiderX = this.spiderX.trim();
    p.allowInsecure = this.allowInsecure;
    return p;
  }

  save(): void {
    let p = this.collect();
    if (p.server === '' || p.serverPort <= 0 || p.serverPort > 65535) {
      promptAction.showToast({ message: '请填写有效的服务器地址与端口' });
      return;
    }
    if ((p.configType === 'vless' || p.configType === 'vmess') && p.uuid === '') {
      promptAction.showToast({ message: '请填写 UUID' });
      return;
    }
    if ((p.configType === 'trojan' || p.configType === 'shadowsocks') && p.password === '') {
      promptAction.showToast({ message: '请填写密码' });
      return;
    }
    ProfileStore.loadProfiles().then((list: Profile[]) => {
      if (p.id === '') {
        // 新建：生成 id（复用分享链接解析里的生成逻辑太重，这里用时间戳+随机）
        p.id = 'pf-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 100000).toString(36);
        list.push(p);
      } else {
        let found = false;
        for (let i = 0; i < list.length; i++) {
          if (list[i].id === p.id) {
            list[i] = p;
            found = true;
            break;
          }
        }
        if (!found) {
          list.push(p);
        }
      }
      return ProfileStore.saveProfiles(list);
    }).then(() => {
      promptAction.showToast({ message: '已保存' });
      router.back();
    }).catch(() => {
      promptAction.showToast({ message: '保存失败' });
    });
  }

  build() {
    Column() {
      Row() {
        Text('取消').fontSize(15).fontColor('#8A94A8').onClick(() => { router.back(); })
        Blank()
        Text(this.editingId === '' ? '添加节点' : '编辑节点').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#E5EDFF')
        Blank()
        Text('保存').fontSize(15).fontColor('#3B82F6').onClick(() => { this.save(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      List({ space: 10 }) {
        ListItem() {
          Column({ space: 10 }) {
            Text('基础').fontSize(13).fontColor('#8A94A8')
            this.field('备注名', this.name, (v: string) => { this.name = v; }, '我的节点')
            Row({ space: 10 }) {
              Text('协议').fontSize(14).fontColor('#E5EDFF').width(90)
              Select(TYPE_LABELS.map((t: string): SelectOption => { return { value: t }; }))
                .selected(this.typeIndex)
                .value(TYPE_LABELS[this.typeIndex])
                .fontColor('#E5EDFF')
                .onSelect((index: number) => { this.typeIndex = index; })
                .layoutWeight(1)
            }.width('100%')
            this.field('服务器地址', this.server, (v: string) => { this.server = v; }, 'example.com')
            this.field('端口', this.serverPort, (v: string) => { this.serverPort = v; }, '443')
          }
          .width('100%').padding(14).borderRadius(12).backgroundColor('#151E31')
        }

        ListItem() {
          Column({ space: 10 }) {
            Text('认证').fontSize(13).fontColor('#8A94A8')
            if (this.typeIndex === 0 || this.typeIndex === 1) {
              this.field('UUID', this.uuid, (v: string) => { this.uuid = v; }, 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx')
              if (this.typeIndex === 0) {
                this.field('Flow', this.flow, (v: string) => { this.flow = v; }, 'xtls-rprx-vision(可空)')
              }
              if (this.typeIndex === 1) {
                this.field('alterId', this.alterId, (v: string) => { this.alterId = v; }, '0')
              }
            } else if (this.typeIndex === 2 || this.typeIndex === 3) {
              this.field('密码', this.password, (v: string) => { this.password = v; }, 'password')
              if (this.typeIndex === 3) {
                this.field('加密方式', this.security, (v: string) => { this.security = v; }, 'aes-256-gcm')
              }
            } else {
              this.field('用户名', this.uuid, (v: string) => { this.uuid = v; }, 'user')
              this.field('密码', this.password, (v: string) => { this.password = v; }, 'pass')
            }
          }
          .width('100%').padding(14).borderRadius(12).backgroundColor('#151E31')
        }

        ListItem() {
          Column({ space: 10 }) {
            Text('传输').fontSize(13).fontColor('#8A94A8')
            Row({ space: 10 }) {
              Text('传输层').fontSize(14).fontColor('#E5EDFF').width(90)
              Select(NETWORKS.map((t: string): SelectOption => { return { value: t }; }))
                .selected(this.networkIndex)
                .value(NETWORKS[this.networkIndex])
                .fontColor('#E5EDFF')
                .onSelect((index: number) => { this.networkIndex = index; })
                .layoutWeight(1)
            }.width('100%')
            if (this.networkIndex === 1) {
              this.field('Host', this.host, (v: string) => { this.host = v; }, 'cdn.example.com')
              this.field('Path', this.path, (v: string) => { this.path = v; }, '/path')
            }
            if (this.networkIndex === 2) {
              this.field('serviceName', this.serviceName, (v: string) => { this.serviceName = v; }, 'grpcService')
            }
          }
          .width('100%').padding(14).borderRadius(12).backgroundColor('#151E31')
        }

        ListItem() {
          Column({ space: 10 }) {
            Text('安全(TLS)').fontSize(13).fontColor('#8A94A8')
            Row({ space: 10 }) {
              Text('模式').fontSize(14).fontColor('#E5EDFF').width(90)
              Select(TLS_LABELS.map((t: string): SelectOption => { return { value: t }; }))
                .selected(this.tlsIndex)
                .value(TLS_LABELS[this.tlsIndex])
                .fontColor('#E5EDFF')
                .onSelect((index: number) => { this.tlsIndex = index; })
                .layoutWeight(1)
            }.width('100%')
            if (this.tlsIndex > 0) {
              this.field('SNI', this.sni, (v: string) => { this.sni = v; }, 'example.com')
              this.field('fingerprint', this.fingerprint, (v: string) => { this.fingerprint = v; }, 'chrome')
              if (this.tlsIndex === 2) {
                this.field('publicKey', this.publicKey, (v: string) => { this.publicKey = v; }, 'Reality 公钥')
                this.field('shortId', this.shortId, (v: string) => { this.shortId = v; }, 'Reality shortId')
                this.field('spiderX', this.spiderX, (v: string) => { this.spiderX = v; }, 'https://example.com')
              }
              Row({ space: 10 }) {
                Text('允许不安全证书').fontSize(14).fontColor('#E5EDFF')
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.allowInsecure })
                  .onChange((on: boolean) => { this.allowInsecure = on; })
              }.width('100%')
            }
          }
          .width('100%').padding(14).borderRadius(12).backgroundColor('#151E31')
        }

        ListItem() {
          Column() {
            Button('保存节点').width('100%').height(44).fontSize(16)
              .backgroundColor('#3B82F6').onClick(() => { this.save(); })
          }.width('100%').padding({ top: 4, bottom: 24 })
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, top: 4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B1220')
  }

  @Builder
  field(label: string, value: string, onChange: (v: string) => void, placeholder: string) {
    Row({ space: 10 }) {
      Text(label).fontSize(14).fontColor('#E5EDFF').width(90)
      TextInput({ text: value, placeholder: placeholder })
        .fontSize(14)
        .fontColor('#E5EDFF')
        .placeholderColor('#55617A')
        .height(38)
        .layoutWeight(1)
        .onChange(onChange)
    }.width('100%')
  }
}
