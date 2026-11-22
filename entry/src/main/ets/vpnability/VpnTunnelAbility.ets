import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';
import { ProfileStore, XraySettings } from '../core/ProfileStore';
import { ConfigBuilder } from '../core/ConfigBuilder';
import { LibXray } from '../native/libxray';
import { Profile } from '../model/Profile';

/**
 * VPN 隧道扩展（移植自 v2rayNG CoreVpnService）。
 * 运行于独立进程：选中节点经 want.parameters 传入（preferences 跨进程不保证同步），
 * 各阶段状态写入 files/diag.json 供日志诊断页（UI 进程）查看。
 */
export default class VpnTunnelAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;

  private writeDiag(stage: string, ok: boolean, detail: string): void {
    try {
      let safeDetail = detail.replace(/"/g, "'");
      let diag = '{"stage":"' + stage + '","ok":' + (ok ? 'true' : 'false')
        + ',"detail":"' + safeDetail + '","time":' + Date.now() + '}';
      let file = fs.openSync(this.context.filesDir + '/diag.json',
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, diag);
      fs.closeSync(file.fd);
    } catch (e) {
      hilog.error(0x0000, 'V2RayNG', '%{public}s', 'writeDiag failed');
    }
  }

  onCreate(want: Want): void {
    hilog.info(0x0000, 'V2RayNG', '%{public}s', 'VpnTunnelAbility onCreate');
    let selectedId = '';
    try {
      let p = want.parameters as Record<string, Object>;
      if (p !== undefined && p !== null) {
        selectedId = String(p['selectedId'] ?? '');
      }
    } catch (e) {
      selectedId = '';
    }
    this.startTunnel(selectedId);
  }

  private async startTunnel(selectedId: string): Promise<void> {
    try {
      await ProfileStore.init(this.context);
      let profiles: Profile[] = await ProfileStore.loadProfiles();
      if (selectedId === '') {
        selectedId = await ProfileStore.loadSelectedId();
      }
      let selected: Profile | null = null;
      for (let i = 0; i < profiles.length; i++) {
        if (profiles[i].id === selectedId) {
          selected = profiles[i];
          break;
        }
      }
      if (selected === null) {
        hilog.error(0x0000, 'V2RayNG', '%{public}s', 'no selected profile, abort tunnel');
        this.writeDiag('select', false, 'no selected profile');
        AppStorage.setOrCreate('vpnRunning', false);
        return;
      }
      this.writeDiag('select', true, selected.name);

      this.vpnConnection = vpnExtension.createVpnConnection(this.context);
      let vpnConfig = ConfigBuilder.buildVpnConfig(1500);
      let fd: number = await this.vpnConnection.create(vpnConfig);
      this.tunFd = fd;
      hilog.info(0x0000, 'V2RayNG', 'vpn tun fd: %{public}d', fd);
      this.writeDiag('tun', true, 'fd=' + fd);

      // 初始化核心环境（asset 目录存放 geoip/geosite.dat；设备标识用于 XUDP）
      LibXray.initCoreEnv(this.context.filesDir + '/assets', 'harmonyos-' + this.context.applicationInfo.uid);
      this.writeDiag('initCore', true, this.context.filesDir + '/assets');

      // geo 数据是否已下载（决定路由规则能否引用 geoip:/geosite:）
      let hasGeo = false;
      try {
        hasGeo = fs.accessSync(this.context.filesDir + '/assets/geoip.dat')
          && fs.accessSync(this.context.filesDir + '/assets/geosite.dat');
      } catch (e) {
        hasGeo = false;
      }

      let settings: XraySettings = await ProfileStore.loadSettings();
      let xrayConfig = ConfigBuilder.buildXrayConfig(selected, settings, hasGeo);
      this.writeDiag('config', true, hasGeo ? 'geo rules enabled' : 'geo rules off (dat missing)');

      let ok: boolean = LibXray.startLoop(xrayConfig, fd);
      this.writeDiag('startLoop', ok, ok ? 'xray + hev running' : 'startLoop failed (see hilog)');
      hilog.info(0x0000, 'V2RayNG', 'core startLoop: %{public}s', ok ? 'ok' : 'failed');
      AppStorage.setOrCreate('vpnRunning', ok);
    } catch (err) {
      let e = err as BusinessError;
      hilog.error(0x0000, 'V2RayNG', 'startTunnel fail: %{public}s', JSON.stringify(e));
      this.writeDiag('exception', false, JSON.stringify(e));
      AppStorage.setOrCreate('vpnRunning', false);
    }
  }

  onDestroy(): void {
    hilog.info(0x0000, 'V2RayNG', '%{public}s', 'VpnTunnelAbility onDestroy');
    try {
      LibXray.stopLoop();
    } catch (e) {
      hilog.error(0x0000, 'V2RayNG', 'stopLoop fail: %{public}s', JSON.stringify(e));
    }
    if (this.vpnConnection !== null && this.tunFd >= 0) {
      this.vpnConnection.destroy().then(() => {
        hilog.info(0x0000, 'V2RayNG', '%{public}s', 'vpn destroyed');
      }).catch((err: BusinessError) => {
        hilog.error(0x0000, 'V2RayNG', 'vpn destroy fail: %{public}s', JSON.stringify(err));
      });
      this.tunFd = -1;
      this.vpnConnection = null;
    }
    AppStorage.setOrCreate('vpnRunning', false);
  }
}
