import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProfileStore } from '../core/ProfileStore';
import { ConfigBuilder } from '../core/ConfigBuilder';
import { LibXray } from '../native/libxray';
import { Profile } from '../model/Profile';

/**
 * VPN 隧道扩展（移植自 v2rayNG CoreVpnService）。
 *
 * 数据面：系统 VPN 虚拟网卡(tun fd) -> libxray_ohos(hev-socks5-tunnel + Xray core) -> 代理服务器
 * 与 Android 版差异：Android 用 VpnService.establish()，鸿蒙用 VpnConnection.create() 返回的 fd。
 */
export default class VpnTunnelAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;

  onCreate(want: Want): void {
    hilog.info(0x0000, 'V2RayNG', '%{public}s', 'VpnTunnelAbility onCreate');
    this.startTunnel();
  }

  private async startTunnel(): Promise<void> {
    try {
      await ProfileStore.init(this.context);
      let profiles: Profile[] = await ProfileStore.loadProfiles();
      let selectedId = await ProfileStore.loadSelectedId();
      let selected: Profile | null = null;
      for (let i = 0; i < profiles.length; i++) {
        if (profiles[i].id === selectedId) {
          selected = profiles[i];
          break;
        }
      }
      if (selected === null) {
        hilog.error(0x0000, 'V2RayNG', '%{public}s', 'no selected profile, abort tunnel');
        return;
      }

      this.vpnConnection = vpnExtension.createVpnConnection(this.context);
      let vpnConfig = ConfigBuilder.buildVpnConfig(1500);
      let fd: number = await this.vpnConnection.create(vpnConfig);
      this.tunFd = fd;
      hilog.info(0x0000, 'V2RayNG', 'vpn tun fd: %{public}d', fd);

      // 初始化核心环境（asset 目录存放 geoip/geosite.dat；设备标识用于 XUDP）
      LibXray.initCoreEnv(this.context.filesDir + '/assets', 'harmonyos-' + this.context.applicationInfo.uid);

      let xrayConfig = ConfigBuilder.buildXrayConfig(selected);
      let ok: boolean = LibXray.startLoop(xrayConfig, fd);
      hilog.info(0x0000, 'V2RayNG', 'core startLoop: %{public}s', ok ? 'ok' : 'failed');
      AppStorage.setOrCreate('vpnRunning', ok);
    } catch (err) {
      let e = err as BusinessError;
      hilog.error(0x0000, 'V2RayNG', 'startTunnel fail: %{public}s', JSON.stringify(e));
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
