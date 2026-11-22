import { buffer, util } from '@kit.ArkTS';

/** 节点配置模型（对应 v2rayNG ProfileItem 的精简版） */
export class Profile {
  id: string = '';
  name: string = '';
  configType: string = 'vless'; // vmess | vless | trojan | shadowsocks | socks | http
  server: string = '';
  serverPort: number = 443;
  uuid: string = '';
  password: string = '';
  security: string = 'auto'; // shadowsocks 加密方式
  alterId: number = 0;
  flow: string = '';
  network: string = 'tcp'; // tcp | ws | grpc
  headerType: string = '';
  host: string = '';
  path: string = '';
  serviceName: string = '';
  tls: string = ''; // '' | tls | reality
  sni: string = '';
  fingerprint: string = '';
  publicKey: string = '';
  shortId: string = '';
  spiderX: string = '';
  allowInsecure: boolean = false;
  // 订阅分组归属
  subId: string = '';
  subName: string = '';
  // 一键测速结果：-1 未测，-2 超时/失败，其他为 RTT 毫秒
  testMs: number = -1;
}

export const SUPPORTED_TYPES: string[] = ['vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'http'];

function b64Decode(input: string): string {
  let s = input.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4 !== 0) {
    s += '=';
  }
  try {
    return buffer.from(s, 'base64').toString('utf-8');
  } catch (e) {
    return '';
  }
}

function newId(): string {
  return util.generateRandomUUID(true);
}

/** 端口安全解析：非法端口返回 0（调用方据此跳过坏节点，避免出现 "host:null"） */
function toPort(s: string): number {
  let n = Number(s);
  if (!Number.isFinite(n) || n <= 0 || n > 65535) {
    return 0;
  }
  return Math.floor(n);
}

/** 兼容旧持久化数据：修复缺失字段与非法端口（旧版本曾把 NaN 序列化成 null） */
export function sanitizeProfile(p: Profile): Profile {
  if (p.serverPort === null || p.serverPort === undefined || !Number.isFinite(p.serverPort)
    || p.serverPort <= 0 || p.serverPort > 65535) {
    p.serverPort = 443;
  }
  if (p.subId === null || p.subId === undefined) {
    p.subId = '';
  }
  if (p.subName === null || p.subName === undefined) {
    p.subName = '';
  }
  if (p.testMs === null || p.testMs === undefined || !Number.isFinite(p.testMs)) {
    p.testMs = -1;
  }
  if (p.name === null || p.name === undefined) {
    p.name = '';
  }
  return p;
}

/** 反向生成 v2rayN 系分享链接（对应 v2rayNG ProfileItem.toUri） */
export function toShareLink(p: Profile): string {
  if (p.configType === 'vmess') {
    let tlsValue: string = p.tls === '' ? '' : 'tls';
    let obj: Record<string, Object> = {
      'v': '2', 'ps': p.name, 'add': p.server, 'port': p.serverPort,
      'id': p.uuid, 'aid': p.alterId, 'net': p.network, 'type': p.headerType,
      'host': p.host, 'path': p.path, 'tls': tlsValue, 'sni': p.sni, 'fp': p.fingerprint
    };
    return 'vmess://' + buffer.from(JSON.stringify(obj), 'utf-8').toString('base64');
  }
  if (p.configType === 'vless' || p.configType === 'trojan') {
    let userinfo: string = p.configType === 'vless' ? p.uuid : p.password;
    let query: string = 'type=' + p.network;
    if (p.host !== '') {
      query += '&host=' + encodeURIComponent(p.host);
    }
    if (p.path !== '') {
      query += '&path=' + encodeURIComponent(p.path);
    }
    if (p.serviceName !== '') {
      query += '&serviceName=' + encodeURIComponent(p.serviceName);
    }
    if (p.tls !== '') {
      query += '&security=' + p.tls;
    }
    if (p.sni !== '') {
      query += '&sni=' + encodeURIComponent(p.sni);
    }
    if (p.fingerprint !== '') {
      query += '&fp=' + p.fingerprint;
    }
    if (p.flow !== '') {
      query += '&flow=' + p.flow;
    }
    if (p.publicKey !== '') {
      query += '&pbk=' + p.publicKey;
    }
    if (p.shortId !== '') {
      query += '&sid=' + p.shortId;
    }
    if (p.spiderX !== '') {
      query += '&spx=' + encodeURIComponent(p.spiderX);
    }
    return p.configType + '://' + userinfo + '@' + p.server + ':' + p.serverPort + '?' + query + '#'
      + encodeURIComponent(p.name);
  }
  if (p.configType === 'shadowsocks') {
    let mp: string = buffer.from(p.security + ':' + p.password, 'utf-8').toString('base64');
    return 'ss://' + mp + '@' + p.server + ':' + p.serverPort + '#' + encodeURIComponent(p.name);
  }
  return '';
}

/** 解析 v2rayN 系分享链接（vmess/vless/trojan/ss） */
export function parseShareLink(url: string): Profile | null {
  let u = url.trim();
  if (u.startsWith('vmess://')) {
    try {
      let obj: Record<string, Object> = JSON.parse(b64Decode(u.substring(8))) as Record<string, Object>;
      let p = new Profile();
      p.id = newId();
      p.configType = 'vmess';
      p.name = String(obj['ps'] ?? '');
      p.server = String(obj['add'] ?? '');
      p.serverPort = toPort(String(obj['port'] ?? '443'));
      p.uuid = String(obj['id'] ?? '');
      p.alterId = Number(obj['aid'] ?? 0);
      p.network = String(obj['net'] ?? 'tcp');
      p.headerType = String(obj['type'] ?? '');
      p.host = String(obj['host'] ?? '');
      p.path = String(obj['path'] ?? '');
      p.tls = String(obj['tls'] ?? '') === 'tls' ? 'tls' : '';
      p.sni = String(obj['sni'] ?? '');
      p.fingerprint = String(obj['fp'] ?? '');
      if (p.server === '' || p.uuid === '' || p.serverPort === 0) {
        return null;
      }
      if (p.name === '') {
        p.name = p.server;
      }
      return p;
    } catch (e) {
      return null;
    }
  }
  if (u.startsWith('vless://') || u.startsWith('trojan://')) {
    let scheme = u.startsWith('vless://') ? 'vless' : 'trojan';
    let rest = u.substring(scheme.length + 3);
    let hashIdx = rest.indexOf('#');
    let frag = hashIdx >= 0 ? rest.substring(hashIdx + 1) : '';
    let main = hashIdx >= 0 ? rest.substring(0, hashIdx) : rest;
    let qIdx = main.indexOf('?');
    let query = qIdx >= 0 ? main.substring(qIdx + 1) : '';
    main = qIdx >= 0 ? main.substring(0, qIdx) : main;
    let atIdx = main.lastIndexOf('@');
    if (atIdx < 0) {
      return null;
    }
    let userinfo = decodeURIComponent(main.substring(0, atIdx));
    let hostport = main.substring(atIdx + 1);
    let colon = hostport.lastIndexOf(':');
    if (colon < 0) {
      return null;
    }
    let host = hostport.substring(0, colon);
    let port = toPort(hostport.substring(colon + 1));
    let params: Record<string, string> = {};
    query.split('&').forEach((kv: string) => {
      let i = kv.indexOf('=');
      if (i > 0) {
        params[kv.substring(0, i)] = decodeURIComponent(kv.substring(i + 1));
      }
    });
    let p = new Profile();
    p.id = newId();
    p.configType = scheme;
    p.name = decodeURIComponent(frag) === '' ? host : decodeURIComponent(frag);
    p.server = host;
    p.serverPort = port;
    if (scheme === 'vless') {
      p.uuid = userinfo;
      p.flow = params['flow'] ?? '';
    } else {
      p.password = userinfo;
    }
    p.network = params['type'] ?? 'tcp';
    p.host = params['host'] ?? '';
    p.path = params['path'] ?? '';
    p.serviceName = params['serviceName'] ?? '';
    p.headerType = params['headerType'] ?? '';
    let sec = params['security'] ?? '';
    p.tls = sec === 'tls' || sec === 'reality' ? sec : '';
    p.sni = params['sni'] ?? '';
    p.fingerprint = params['fp'] ?? '';
    p.publicKey = params['pbk'] ?? '';
    p.shortId = params['sid'] ?? '';
    p.spiderX = params['spx'] ?? '';
    if (p.server === '' || p.serverPort === 0 || (scheme === 'vless' ? p.uuid === '' : p.password === '')) {
      return null;
    }
    return p;
  }
  if (u.startsWith('ss://')) {
    let rest = u.substring(5);
    let hashIdx = rest.indexOf('#');
    let frag = hashIdx >= 0 ? rest.substring(hashIdx + 1) : '';
    let main = hashIdx >= 0 ? rest.substring(0, hashIdx) : rest;
    let atIdx = main.lastIndexOf('@');
    if (atIdx >= 0) {
      // ss://base64(method:pass)@host:port
      let methodpass = b64Decode(main.substring(0, atIdx));
      let mc = methodpass.indexOf(':');
      if (mc < 0) {
        return null;
      }
      let hostport = main.substring(atIdx + 1);
      let colon = hostport.lastIndexOf(':');
      if (colon < 0) {
        return null;
      }
      let port = toPort(hostport.substring(colon + 1));
      if (port === 0) {
        return null;
      }
      let p = new Profile();
      p.id = newId();
      p.configType = 'shadowsocks';
      p.name = decodeURIComponent(frag) === '' ? hostport : decodeURIComponent(frag);
      p.server = hostport.substring(0, colon);
      p.serverPort = port;
      p.security = methodpass.substring(0, mc);
      p.password = methodpass.substring(mc + 1);
      return p;
    } else {
      // ss://base64(method:pass@host:port)
      let all = b64Decode(main);
      let mc = all.indexOf(':');
      let ac = all.lastIndexOf('@');
      if (mc < 0 || ac < 0) {
        return null;
      }
      let hostport = all.substring(ac + 1);
      let colon = hostport.lastIndexOf(':');
      if (colon < 0) {
        return null;
      }
      let port = toPort(hostport.substring(colon + 1));
      if (port === 0) {
        return null;
      }
      let p = new Profile();
      p.id = newId();
      p.configType = 'shadowsocks';
      p.name = decodeURIComponent(frag) === '' ? '' : decodeURIComponent(frag);
      p.security = all.substring(0, mc);
      p.password = all.substring(mc + 1, ac);
      p.server = hostport.substring(0, colon);
      p.serverPort = port;
      if (p.name === '') {
        p.name = p.server;
      }
      return p;
    }
  }
  return null;
}
