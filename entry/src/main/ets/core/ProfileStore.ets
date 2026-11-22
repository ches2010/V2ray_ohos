import { preferences } from '@kit.ArkData';
import { buffer, util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { Profile, parseShareLink, sanitizeProfile } from '../model/Profile';

/** 订阅分组信息 */
export class SubscriptionInfo {
  id: string = '';
  name: string = '';
  url: string = '';
  count: number = 0;
  lastUpdated: number = 0; // epoch ms，0 表示未更新过
}

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
      let out: Profile[] = [];
      for (let i = 0; i < arr.length; i++) {
        out.push(sanitizeProfile(arr[i]));
      }
      return out;
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

  // ---------------- 订阅分组管理 ----------------

  static async loadSubscriptions(): Promise<SubscriptionInfo[]> {
    let store = await ProfileStore.ensure();
    let raw = String(await store.get('subscriptions_json', '[]'));
    try {
      return JSON.parse(raw) as SubscriptionInfo[];
    } catch (e) {
      return [];
    }
  }

  private static async saveSubscriptions(list: SubscriptionInfo[]): Promise<void> {
    let store = await ProfileStore.ensure();
    await store.put('subscriptions_json', JSON.stringify(list));
    await store.flush();
  }

  /** 从订阅内容（base64 或明文多行链接）解析节点，并打上分组标记 */
  private static parseNodes(content: string, subId: string, subName: string): Profile[] {
    let text = content.trim();
    if (!text.startsWith('vmess://') && !text.startsWith('vless://') && !text.startsWith('trojan://')
      && !text.startsWith('ss://')) {
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
    let nodes: Profile[] = [];
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i].trim();
      if (line === '') {
        continue;
      }
      let p = parseShareLink(line);
      if (p !== null) {
        p.subId = subId;
        p.subName = subName;
        nodes.push(p);
      }
    }
    return nodes;
  }

  /** 新增订阅：解析内容、替换同组旧节点、记录订阅信息。返回节点数。 */
  static async addSubscription(name: string, url: string, content: string): Promise<number> {
    let subId = util.generateRandomUUID(true);
    let nodes = ProfileStore.parseNodes(content, subId, name);
    let list = await ProfileStore.loadProfiles();
    let kept: Profile[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].subId !== subId) {
        kept.push(list[i]);
      }
    }
    for (let i = 0; i < nodes.length; i++) {
      kept.push(nodes[i]);
    }
    await ProfileStore.saveProfiles(kept);
    let subs = await ProfileStore.loadSubscriptions();
    let info = new SubscriptionInfo();
    info.id = subId;
    info.name = name;
    info.url = url;
    info.count = nodes.length;
    info.lastUpdated = Date.now();
    subs.push(info);
    await ProfileStore.saveSubscriptions(subs);
    return nodes.length;
  }

  /** 刷新已有订阅：重新解析并整体替换该组节点。返回节点数（订阅不存在返回 -1）。 */
  static async refreshSubscription(subId: string, content: string): Promise<number> {
    let subs = await ProfileStore.loadSubscriptions();
    let target: SubscriptionInfo | null = null;
    for (let i = 0; i < subs.length; i++) {
      if (subs[i].id === subId) {
        target = subs[i];
        break;
      }
    }
    if (target === null) {
      return -1;
    }
    let nodes = ProfileStore.parseNodes(content, subId, target.name);
    let list = await ProfileStore.loadProfiles();
    let kept: Profile[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].subId !== subId) {
        kept.push(list[i]);
      }
    }
    for (let i = 0; i < nodes.length; i++) {
      kept.push(nodes[i]);
    }
    await ProfileStore.saveProfiles(kept);
    target.count = nodes.length;
    target.lastUpdated = Date.now();
    await ProfileStore.saveSubscriptions(subs);
    return nodes.length;
  }

  /** 删除订阅及其全部节点 */
  static async deleteSubscription(subId: string): Promise<void> {
    let list = await ProfileStore.loadProfiles();
    let kept: Profile[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].subId !== subId) {
        kept.push(list[i]);
      }
    }
    await ProfileStore.saveProfiles(kept);
    let subs = await ProfileStore.loadSubscriptions();
    let keptSubs: SubscriptionInfo[] = [];
    for (let i = 0; i < subs.length; i++) {
      if (subs[i].id !== subId) {
        keptSubs.push(subs[i]);
      }
    }
    await ProfileStore.saveSubscriptions(keptSubs);
  }
}
