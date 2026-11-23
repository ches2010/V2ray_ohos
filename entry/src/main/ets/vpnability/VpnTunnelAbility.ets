import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProfileStore, XraySettings } from '../core/ProfileStore';
import { ConfigBuilder } from '../core/ConfigBuilder';
import { LibXray } from '../native/libxray';
import { Profile, sanitizeProfile } from '../model/Profile';
import { NativeStatus, RuntimeSnapshot } from '../core/RuntimeSnapshot';
import { RuntimeStore } from '../core/RuntimeStore';
import { BUNDLE_NAME } from '../core/VpnController';

/** VPN 进程持有 TUN 和 native；UI 读取它发布的唯一运行快照。 */
export default class VpnTunnelAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;
  private snapshot: RuntimeSnapshot = new RuntimeSnapshot();
  private heartbeat: number = -1;
  private closing: boolean = false;

  onCreate(want: Want): void {
    this.startTunnel(want).catch((e: BusinessError) => {
      this.fail('startup', e.code + ': ' + e.message);
    });
  }

  private publish(): void {
    try {
      RuntimeStore.write(this.context, this.snapshot);
    } catch (e) {
      hilog.error(0, 'V2ray', '%{public}s', 'VPN 状态快照写入失败');
    }
  }

  private async startTunnel(want: Want): Promise<void> {
    RuntimeStore.init(this.context);
    let params: Record<string, Object> = want.parameters as Record<string, Object>;
    this.snapshot.sessionId = String(params?.['sessionId'] ?? '');
    this.snapshot.state = 'starting';
    this.snapshot.stage = 'profile';
    this.publish();

    let selected: Profile | null = null;
    let settings: XraySettings = new XraySettings();
    let profileJson: string = String(params?.['profileJson'] ?? '');
    let settingsJson: string = String(params?.['settingsJson'] ?? '');
    if (profileJson !== '') {
      selected = sanitizeProfile(JSON.parse(profileJson) as Profile);
      if (settingsJson !== '') {
        settings = JSON.parse(settingsJson) as XraySettings;
      }
    } else {
      // 兼容系统重新拉起扩展；主动连接优先使用 Want 中的完整配置快照。
      await ProfileStore.init(this.context);
      let list: Profile[] = await ProfileStore.loadProfiles();
      let id: string = String(params?.['selectedId'] ?? await ProfileStore.loadSelectedId());
      for (let p of list) {
        if (p.id === id) {
          selected = p;
          break;
        }
      }
      settings = await ProfileStore.loadSettings();
    }
    if (selected === null || selected.server === '' || this.closing) {
      await this.fail('profile', '未找到有效节点，未建立 VPN');
      return;
    }
    this.snapshot.nodeName = selected.name;
    this.snapshot.protocol = selected.configType;
    this.snapshot.transport = selected.network;
    this.snapshot.tls = selected.tls;
    this.snapshot.muxEnabled = settings.enableMux;
    this.snapshot.sniffingEnabled = settings.enableSniffing;
    this.snapshot.geoIpReady = RuntimeStore.fileReady(this.context.filesDir + '/assets/geoip.dat');
    this.snapshot.geoSiteReady = RuntimeStore.fileReady(this.context.filesDir + '/assets/geosite.dat');
    this.snapshot.geoRulesEnabled = this.snapshot.geoIpReady && this.snapshot.geoSiteReady;
    this.snapshot.routeMode = this.snapshot.geoRulesEnabled ? settings.routeMode : 0;
    this.snapshot.excludedBundle = BUNDLE_NAME;
    this.snapshot.stage = 'tun';
    this.publish();

    this.vpnConnection = vpnExtension.createVpnConnection(this.context);
    // 鸿蒙官方 blockedApplications：自身应用的 Xray/DNS/socket 走物理网络，
    // 防止出站再次进入 TUN 的循环。其他应用仍按 VPN routes 被代理。
    let config: vpnExtension.VpnConfig = ConfigBuilder.buildVpnConfig(1500, this.snapshot.excludedBundle);
    let fd: number = await this.vpnConnection.create(config);
    this.snapshot.active = true;
    if (this.closing) {
      await this.cleanup();
      return;
    }
    this.snapshot.stage = 'native-start';
    this.publish();
    LibXray.initCoreEnv(this.context.filesDir + '/assets', 'harmonyos');
    let xrayConfig: string = ConfigBuilder.buildXrayConfig(selected, settings,
      this.snapshot.geoRulesEnabled, this.context.filesDir);
    let ok: boolean = LibXray.startLoop(xrayConfig, fd);
    this.snapshot.native = JSON.parse(LibXray.getCoreStatus()) as NativeStatus;
    if (!ok || !this.snapshot.native.running) {
      await this.fail('native-start', this.snapshot.native.lastError || '核心未成功启动');
      return;
    }
    this.snapshot.state = 'running';
    this.snapshot.stage = 'running';
    this.publish();
    // 一直发布 native 存活及探测结果，不让 selftest 覆盖连接状态。
    this.heartbeat = setInterval(() => { this.updateRuntime(); }, 1000);
  }

  private updateRuntime(): void {
    if (this.closing) {
      return;
    }
    try {
      this.snapshot.native = JSON.parse(LibXray.getCoreStatus()) as NativeStatus;
      if (!this.snapshot.native.running || this.snapshot.native.hevExited) {
        this.fail('native-exit', this.snapshot.native.lastError || 'tun2socks 已退出');
        return;
      }
      this.publish();
    } catch (e) {
      this.fail('runtime', '读取核心运行状态失败');
    }
  }

  private async cleanup(): Promise<void> {
    if (this.heartbeat >= 0) {
      clearInterval(this.heartbeat);
      this.heartbeat = -1;
    }
    try {
      LibXray.stopLoop();
    } catch (e) {
      hilog.error(0, 'V2ray', '%{public}s', '核心停止失败');
    }
    let conn: vpnExtension.VpnConnection | null = this.vpnConnection;
    this.vpnConnection = null;
    if (conn !== null) {
      try {
        await conn.destroy();
      } catch (e) {
        this.snapshot.errorText += '；系统 VPN 销毁失败，请在系统设置断开 VPN';
        this.snapshot.native.running = false;
        this.snapshot.native.xrayStarted = false;
        // 销毁未成功时保留 active，让 UI 继续提供断开入口，不伪装成已断开。
        this.publish();
        return;
      }
    }
    this.snapshot.active = false;
    this.snapshot.native.running = false;
    this.snapshot.native.xrayStarted = false;
  }

  private async fail(stage: string, message: string): Promise<void> {
    this.closing = true;
    this.snapshot.state = 'error';
    this.snapshot.stage = stage;
    this.snapshot.errorText = RuntimeStore.redact(message);
    await this.cleanup(); // 失败即回收 TUN，不能留一个无出口的系统 VPN
    this.publish();
  }

  onDestroy(): void {
    this.closing = true;
    this.snapshot.state = 'stopping';
    this.snapshot.stage = 'stopping';
    this.publish();
    this.cleanup().then(() => {
      this.snapshot.state = 'stopped';
      this.snapshot.stage = 'stopped';
      this.publish();
    });
  }
}
