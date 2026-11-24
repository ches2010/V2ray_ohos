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
    let want: Want = { bundleName: BUNDLE_NAME, abilityName: VPN_ABILITY_NAME };
    try {
      await vpnExtension.stopVpnExtensionAbility(want);
    } catch (e) {
      let state: RuntimeSnapshot = RuntimeStore.read(context) ?? new RuntimeSnapshot();
      state.state = 'error';
      state.errorText = RuntimeStore.redact(String(e));
      RuntimeStore.write(context, state);
      throw new Error(String(e));
    }
    // 等待 VPN 进程在 onDestroy 里发布 stopped。UI 在此期间不写快照：
    // 若扩展尚未被系统销毁，它的心跳仍会写 running，UI 抢写会造成
    // “启动中/异常”与“隧道已启动”来回跳动（真机已复现）。
    for (let i = 0; i < 20; i++) {
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 300); });
      let cur: RuntimeSnapshot | null = RuntimeStore.read(context);
      if (cur !== null && (cur.state === 'stopped' || cur.state === 'error') && !cur.active) {
        return;
      }
    }
    // 兜底：仅在心跳已停（进程消失）时才落一个确定的停止态；
    // 心跳仍在说明系统未响应停止请求，再发一次停止指令后短暂等待。
    let cur: RuntimeSnapshot | null = RuntimeStore.read(context);
    if (cur !== null && cur.state === 'running' && Date.now() - cur.updatedAt < 4000) {
      try {
        await vpnExtension.stopVpnExtensionAbility(want);
      } catch (e) {
        // 忽略二次停止失败，交由下方按停止态收尾
      }
      for (let i = 0; i < 10; i++) {
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 300); });
        cur = RuntimeStore.read(context);
        if (cur !== null && (cur.state === 'stopped' || cur.state === 'error') && !cur.active) {
          return;
        }
      }
    }
    let final: RuntimeSnapshot = cur ?? new RuntimeSnapshot();
    final.state = 'stopped';
    final.stage = 'stopped';
    final.active = false;
    final.native.running = false;
    final.native.xrayStarted = false;
    RuntimeStore.write(context, final);
  }
}
