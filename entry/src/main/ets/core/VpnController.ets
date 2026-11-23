import { vpnExtension } from '@kit.NetworkKit';
import { Want, common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Profile } from '../model/Profile';
import { XraySettings } from './ProfileStore';
import { RuntimeSnapshot } from './RuntimeSnapshot';
import { RuntimeStore } from './RuntimeStore';

export const BUNDLE_NAME: string = 'com.v2ray.harmony';
export const VPN_ABILITY_NAME: string = 'VpnTunnelAbility';

/** 启动请求不是隧道成功；运行状态由 VPN 进程心跳确认。 */
export class VpnController {
  static async start(context: common.Context, profile: Profile, settings: XraySettings): Promise<void> {
    RuntimeStore.init(context);
    let state: RuntimeSnapshot = new RuntimeSnapshot();
    state.sessionId = util.generateRandomUUID(true);
    state.state = 'starting';
    state.stage = 'request';
    state.nodeName = profile.name;
    state.protocol = profile.configType;
    state.transport = profile.network;
    state.tls = profile.tls;
    RuntimeStore.write(context, state);
    // 传递完整配置快照，不在 VPN 进程依赖 preferences 的缓存是否已更新。
    // 不记录 Want 或分享链接，避免把节点凭据写到诊断日志。
    let params: Record<string, Object> = {
      'sessionId': state.sessionId,
      'selectedId': profile.id,
      'profileJson': JSON.stringify(profile),
      'settingsJson': JSON.stringify(settings)
    };
    let want: Want = { bundleName: BUNDLE_NAME, abilityName: VPN_ABILITY_NAME, parameters: params };
    try {
      await vpnExtension.startVpnExtensionAbility(want);
    } catch (e) {
      state.state = 'error';
      state.stage = 'authorization';
      state.errorText = RuntimeStore.redact(String(e));
      RuntimeStore.write(context, state);
      throw new Error(String(e));
    }
  }

  static async stop(context: common.Context): Promise<void> {
    let state: RuntimeSnapshot = RuntimeStore.read(context) ?? new RuntimeSnapshot();
    state.state = 'stopping';
    state.stage = 'stop-request';
    RuntimeStore.write(context, state);
    let want: Want = { bundleName: BUNDLE_NAME, abilityName: VPN_ABILITY_NAME };
    try {
      await vpnExtension.stopVpnExtensionAbility(want);
      state.state = 'stopped';
      state.stage = 'stopped';
      state.active = false;
      state.native.running = false;
      state.native.xrayStarted = false;
      RuntimeStore.write(context, state);
    } catch (e) {
      state.state = 'error';
      state.errorText = RuntimeStore.redact(String(e));
      RuntimeStore.write(context, state);
      throw new Error(String(e));
    }
  }
}
