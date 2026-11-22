import { vpnExtension } from '@kit.NetworkKit';
import { Profile } from '../model/Profile';

/** Xray JSON 配置与 VPN VpnConfig 生成（对应 v2rayNG CoreConfigManager / CoreOutboundBuilder 精简版） */
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

  private static buildStreamSettings(p: Profile): Record<string, Object> {
    let stream: Record<string, Object> = { 'network': p.network };
    if (p.tls === 'tls') {
      stream['security'] = 'tls';
      let tls: Record<string, Object> = { 'serverName': p.sni === '' ? (p.host === '' ? p.server : p.host) : p.sni };
      if (p.allowInsecure) {
        tls['allowInsecure'] = true;
      }
      if (p.fingerprint !== '') {
        tls['fingerprint'] = p.fingerprint;
      }
      stream['tlsSettings'] = tls;
    } else if (p.tls === 'reality') {
      stream['security'] = 'reality';
      let reality: Record<string, Object> = {
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
      let ws: Record<string, Object> = { 'path': p.path === '' ? '/' : p.path };
      if (p.host !== '') {
        let headers: Record<string, string> = { 'Host': p.host };
        ws['headers'] = headers;
      }
      stream['wsSettings'] = ws;
    } else if (p.network === 'grpc') {
      stream['grpcSettings'] = { 'serviceName': p.serviceName };
    }
    return stream;
  }

  private static buildProxyOutbound(p: Profile): Record<string, Object> | null {
    let stream = ConfigBuilder.buildStreamSettings(p);
    if (p.configType === 'vmess') {
      let user: Record<string, Object> = { 'id': p.uuid, 'alterId': p.alterId, 'security': 'auto' };
      let vnext: Array<Record<string, Object>> = [
        { 'address': p.server, 'port': p.serverPort, 'users': [user] }
      ];
      return { 'tag': 'proxy', 'protocol': 'vmess', 'settings': { 'vnext': vnext }, 'streamSettings': stream };
    }
    if (p.configType === 'vless') {
      let user: Record<string, Object> = { 'id': p.uuid, 'encryption': 'none' };
      if (p.flow !== '') {
        user['flow'] = p.flow;
      }
      let vnext: Array<Record<string, Object>> = [
        { 'address': p.server, 'port': p.serverPort, 'users': [user] }
      ];
      return { 'tag': 'proxy', 'protocol': 'vless', 'settings': { 'vnext': vnext }, 'streamSettings': stream };
    }
    if (p.configType === 'trojan') {
      let server: Record<string, Object> = { 'address': p.server, 'port': p.serverPort, 'password': p.password };
      return { 'tag': 'proxy', 'protocol': 'trojan', 'settings': { 'servers': [server] }, 'streamSettings': stream };
    }
    if (p.configType === 'shadowsocks') {
      let server: Record<string, Object> = {
        'address': p.server, 'port': p.serverPort, 'method': p.security, 'password': p.password
      };
      return { 'tag': 'proxy', 'protocol': 'shadowsocks', 'settings': { 'servers': [server] } };
    }
    if (p.configType === 'socks') {
      let user: Record<string, Object> = { 'user': p.uuid, 'passType': 'password', 'pass': p.password };
      let server: Record<string, Object> = { 'address': p.server, 'port': p.serverPort, 'users': [user] };
      return { 'tag': 'proxy', 'protocol': 'socks', 'settings': { 'servers': [server] } };
    }
    if (p.configType === 'http') {
      let user: Record<string, Object> = { 'user': p.uuid, 'pass': p.password };
      let server: Record<string, Object> = { 'address': p.server, 'port': p.serverPort, 'users': [user] };
      return { 'tag': 'proxy', 'protocol': 'http', 'settings': { 'servers': [server] } };
    }
    return null;
  }

  /** 生成 Xray 核心配置 JSON（socks inbound 由 native 层 tun2socks 接入） */
  static buildXrayConfig(p: Profile): string {
    let proxy = ConfigBuilder.buildProxyOutbound(p);
    let outbounds: Array<Object> = [];
    if (proxy !== null) {
      outbounds.push(proxy);
    }
    outbounds.push({ 'tag': 'direct', 'protocol': 'freedom' });
    let config: Record<string, Object> = {
      'log': { 'loglevel': 'warning' },
      'inbounds': [
        {
          'tag': 'socks',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': { 'udp': true, 'auth': 'noauth' }
        }
      ],
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          { 'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct' }
        ]
      }
    };
    return JSON.stringify(config);
  }
}
