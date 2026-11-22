import { vpnExtension } from '@kit.NetworkKit';
import { Profile } from '../model/Profile';
import { XraySettings } from './ProfileStore';

type JsonObj = Record<string, Object>;

/** Xray JSON 配置与 VPN VpnConfig 生成（对应 v2rayNG CoreConfigManager 精简版） */
export class ConfigBuilder {
  /** 生成 VPN 虚拟网卡配置（对应 CoreVpnService.configureNetworkSettings） */
  static buildVpnConfig(mtu: number): vpnExtension.VpnConfig {
    let config: vpnExtension.VpnConfig = {
      addresses: [
        { address: { address: '10.111.222.1', family: 1 }, prefixLength: 24 }
      ],
      routes: [
        {
          interface: 'vpn-tun',
          destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
          gateway: { address: '0.0.0.0', family: 1 },
          hasGateway: false,
          isDefaultRoute: true
        }
      ],
      mtu: mtu,
      dnsAddresses: ['223.5.5.5', '8.8.8.8'],
      isIPv4Accepted: true,
      isIPv6Accepted: false,
      isBlocking: false,
      isInternal: false,
      trustedApplications: [],
      blockedApplications: []
    };
    return config;
  }

  private static buildStreamSettings(p: Profile): JsonObj {
    let stream: JsonObj = { 'network': p.network };
    if (p.tls === 'tls') {
      stream['security'] = 'tls';
      let serverName: string = p.sni === '' ? (p.host === '' ? p.server : p.host) : p.sni;
      let tls: JsonObj = { 'serverName': serverName };
      if (p.allowInsecure) {
        tls['allowInsecure'] = true;
      }
      if (p.fingerprint !== '') {
        tls['fingerprint'] = p.fingerprint;
      }
      stream['tlsSettings'] = tls;
    } else if (p.tls === 'reality') {
      stream['security'] = 'reality';
      let reality: JsonObj = {
        'serverName': p.sni === '' ? p.server : p.sni,
        'fingerprint': p.fingerprint === '' ? 'chrome' : p.fingerprint,
        'publicKey': p.publicKey,
        'shortId': p.shortId
      };
      if (p.spiderX !== '') {
        reality['spiderX'] = p.spiderX;
      }
      stream['realitySettings'] = reality;
    } else {
      stream['security'] = 'none';
    }
    if (p.network === 'ws') {
      let wsPath: string = p.path === '' ? '/' : p.path;
      let ws: JsonObj = { 'path': wsPath };
      if (p.host !== '') {
        let headers: JsonObj = { 'Host': p.host };
        ws['headers'] = headers;
      }
      stream['wsSettings'] = ws;
    } else if (p.network === 'grpc') {
      let grpc: JsonObj = { 'serviceName': p.serviceName };
      stream['grpcSettings'] = grpc;
    }
    return stream;
  }

  private static buildProxyOutbound(p: Profile): JsonObj | null {
    let stream: JsonObj = ConfigBuilder.buildStreamSettings(p);
    if (p.configType === 'vmess') {
      let user: JsonObj = { 'id': p.uuid, 'alterId': p.alterId, 'security': 'auto' };
      let users: Array<Object> = [user];
      let vnextEntry: JsonObj = { 'address': p.server, 'port': p.serverPort, 'users': users };
      let vnext: Array<Object> = [vnextEntry];
      let settings: JsonObj = { 'vnext': vnext };
      return { 'tag': 'proxy', 'protocol': 'vmess', 'settings': settings, 'streamSettings': stream };
    }
    if (p.configType === 'vless') {
      let user: JsonObj = { 'id': p.uuid, 'encryption': 'none' };
      if (p.flow !== '') {
        user['flow'] = p.flow;
      }
      let users: Array<Object> = [user];
      let vnextEntry: JsonObj = { 'address': p.server, 'port': p.serverPort, 'users': users };
      let vnext: Array<Object> = [vnextEntry];
      let settings: JsonObj = { 'vnext': vnext };
      return { 'tag': 'proxy', 'protocol': 'vless', 'settings': settings, 'streamSettings': stream };
    }
    if (p.configType === 'trojan') {
      let server: JsonObj = { 'address': p.server, 'port': p.serverPort, 'password': p.password };
      let servers: Array<Object> = [server];
      let settings: JsonObj = { 'servers': servers };
      return { 'tag': 'proxy', 'protocol': 'trojan', 'settings': settings, 'streamSettings': stream };
    }
    if (p.configType === 'shadowsocks') {
      let server: JsonObj = {
        'address': p.server, 'port': p.serverPort, 'method': p.security, 'password': p.password
      };
      let servers: Array<Object> = [server];
      let settings: JsonObj = { 'servers': servers };
      return { 'tag': 'proxy', 'protocol': 'shadowsocks', 'settings': settings };
    }
    if (p.configType === 'socks') {
      let user: JsonObj = { 'user': p.uuid, 'passType': 'password', 'pass': p.password };
      let users: Array<Object> = [user];
      let server: JsonObj = { 'address': p.server, 'port': p.serverPort, 'users': users };
      let servers: Array<Object> = [server];
      let settings: JsonObj = { 'servers': servers };
      return { 'tag': 'proxy', 'protocol': 'socks', 'settings': settings };
    }
    if (p.configType === 'http') {
      let user: JsonObj = { 'user': p.uuid, 'pass': p.password };
      let users: Array<Object> = [user];
      let server: JsonObj = { 'address': p.server, 'port': p.serverPort, 'users': users };
      let servers: Array<Object> = [server];
      let settings: JsonObj = { 'servers': servers };
      return { 'tag': 'proxy', 'protocol': 'http', 'settings': settings };
    }
    return null;
  }

  /** 生成 Xray 核心配置 JSON（socks inbound 由 native 层 tun2socks 接入） */
  static buildXrayConfig(p: Profile, st: XraySettings): string {
    let proxy: JsonObj | null = ConfigBuilder.buildProxyOutbound(p);
    let outbounds: Array<Object> = [];
    if (proxy !== null) {
      if (st.enableMux && (p.configType === 'vless' || p.configType === 'vmess' || p.configType === 'trojan')) {
        let mux: JsonObj = { 'enabled': true, 'concurrency': 8 };
        proxy['mux'] = mux;
      }
      outbounds.push(proxy);
    }
    let direct: JsonObj = { 'tag': 'direct', 'protocol': 'freedom' };
    outbounds.push(direct);
    let block: JsonObj = { 'tag': 'block', 'protocol': 'blackhole' };
    outbounds.push(block);

    let socksSettings: JsonObj = { 'udp': true, 'auth': 'noauth' };
    let socksInbound: JsonObj = {
      'tag': 'socks', 'port': 10808, 'listen': '127.0.0.1',
      'protocol': 'socks', 'settings': socksSettings
    };
    if (st.enableSniffing) {
      let destOverride: Array<string> = ['http', 'tls', 'quic'];
      let sniffing: JsonObj = { 'enabled': true, 'destOverride': destOverride };
      socksInbound['sniffing'] = sniffing;
    }
    let inbounds: Array<Object> = [socksInbound];

    // 路由规则（对应 v2rayNG routing：直连私有地址；可选绕过大陆/拦截广告）
    let rules: Array<Object> = [];
    let privateIps: Array<string> = ['geoip:private'];
    let privateRule: JsonObj = { 'type': 'field', 'ip': privateIps, 'outboundTag': 'direct' };
    rules.push(privateRule);
    if (st.blockAds) {
      let adDomains: Array<string> = ['geosite:category-ads-all'];
      let adRule: JsonObj = { 'type': 'field', 'domain': adDomains, 'outboundTag': 'block' };
      rules.push(adRule);
    }
    if (st.routeMode === 1) {
      let cnIps: Array<string> = ['geoip:cn'];
      let cnIpRule: JsonObj = { 'type': 'field', 'ip': cnIps, 'outboundTag': 'direct' };
      rules.push(cnIpRule);
      let cnDomains: Array<string> = ['geosite:cn'];
      let cnDomainRule: JsonObj = { 'type': 'field', 'domain': cnDomains, 'outboundTag': 'direct' };
      rules.push(cnDomainRule);
    }
    let routing: JsonObj = { 'domainStrategy': 'IPIfNonMatch', 'rules': rules };
    let log: JsonObj = { 'loglevel': st.logLevel };
    // 内置 DNS：VPN 内的 DNS 查询由核心代答，避免隧道建立后 DNS 失败
    let dnsServers: Array<string> = ['223.5.5.5', '8.8.8.8'];
    let dns: JsonObj = { 'servers': dnsServers };

    let config: JsonObj = {
      'log': log, 'dns': dns, 'inbounds': inbounds, 'outbounds': outbounds, 'routing': routing
    };
    return JSON.stringify(config);
  }
}

