import { preferences } from '@kit.ArkData';
import { buffer } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { Profile, parseShareLink } from '../model/Profile';

/** 节点与设置的持久化（对应 v2rayNG MMKV 存储，此处用 preferences + JSON） */
export class ProfileStore {
  private static store: preferences.Preferences | null = null;

  static async init(context: common.Context): Promise<void> {
    if (ProfileStore.store === null) {
      ProfileStore.store = await preferences.getPreferences(context, 'v2rayng_store');
    }
  }

  private static async ensure(): Promise<preferences.Preferences> {
    if (ProfileStore.store === null) {
      throw new Error('ProfileStore not initialized');
    }
    return ProfileStore.store;
  }

  static async loadProfiles(): Promise<Profile[]> {
    let store = await ProfileStore.ensure();
    let raw = String(await store.get('profiles_json', '[]'));
    try {
      let arr: Profile[] = JSON.parse(raw) as Profile[];
      return arr;
    } catch (e) {
      return [];
    }
  }

  static async saveProfiles(list: Profile[]): Promise<void> {
    let store = await ProfileStore.ensure();
    await store.put('profiles_json', JSON.stringify(list));
    await store.flush();
  }

  static async loadSelectedId(): Promise<string> {
    let store = await ProfileStore.ensure();
    return String(await store.get('selected_id', ''));
  }

  static async saveSelectedId(id: string): Promise<void> {
    let store = await ProfileStore.ensure();
    await store.put('selected_id', id);
    await store.flush();
  }

  static async addShareLink(url: string): Promise<Profile | null> {
    let p = parseShareLink(url);
    if (p === null) {
      return null;
    }
    let list = await ProfileStore.loadProfiles();
    list.push(p);
    await ProfileStore.saveProfiles(list);
    return p;
  }

  /** 导入订阅：返回成功解析的节点数 */
  static async importSubscription(content: string): Promise<number> {
    let text = content.trim();
    // 订阅内容通常为 base64；也兼容明文多行链接
    if (!text.startsWith('vmess://') && !text.startsWith('vless://') && !text.startsWith('trojan://') && !text.startsWith('ss://')) {
      let decoded = '';
      try {
        decoded = buffer.from(text.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf-8');
      } catch (e) {
        decoded = '';
      }
      if (decoded.indexOf('://') >= 0) {
        text = decoded;
      }
    }
    let lines = text.split('\n');
    let list = await ProfileStore.loadProfiles();
    let added = 0;
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i].trim();
      if (line === '') {
        continue;
      }
      let p = parseShareLink(line);
      if (p !== null) {
        list.push(p);
        added++;
      }
    }
    if (added > 0) {
      await ProfileStore.saveProfiles(list);
    }
    return added;
  }
}
