import { vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export const BUNDLE_NAME = 'com.v2ray.harmony';
export const VPN_ABILITY_NAME = 'VpnTunnelAbility';

/** VPN 连接控制（对应 v2rayNG V2RayServiceManager.startV2Ray/stopV2Ray） */
export class VpnController {
  private static buildWant(selectedId: string): Want {
    let params: Record<string, Object> = { 'selectedId': selectedId };
    let want: Want = {
      deviceId: '',
      bundleName: BUNDLE_NAME,
      abilityName: VPN_ABILITY_NAME,
      parameters: params
    };
    return want;
  }

  /** 启动 VPN（首次会弹系统授权框；选中节点经 want.parameters 传给 VPN 进程） */
  static start(selectedId: string): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (e: BusinessError) => void) => {
      vpnExtension.startVpnExtensionAbility(VpnController.buildWant(selectedId)).then(() => {
        AppStorage.setOrCreate('vpnStarting', true);
        hilog.info(0x0000, 'V2RayNG', 'startVpnExtensionAbility ok');
        resolve();
      }).catch((err: BusinessError) => {
        AppStorage.setOrCreate('vpnRunning', false);
        AppStorage.setOrCreate('vpnStarting', false);
        hilog.error(0x0000, 'V2RayNG', 'startVpnExtensionAbility fail: %{public}s', JSON.stringify(err));
        reject(err);
      });
    });
  }

  /** 停止 VPN */
  static stop(): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (e: BusinessError) => void) => {
      vpnExtension.stopVpnExtensionAbility(VpnController.buildWant('')).then(() => {
        AppStorage.setOrCreate('vpnRunning', false);
        hilog.info(0x0000, 'V2RayNG', 'stopVpnExtensionAbility ok');
        resolve();
      }).catch((err: BusinessError) => {
        hilog.error(0x0000, 'V2RayNG', 'stopVpnExtensionAbility fail: %{public}s', JSON.stringify(err));
        reject(err);
      });
    });
  }
}
