import { vpnExtension } from '@kit.NetworkKit';
import { Profile } from '../model/Profile';
import { XraySettings } from './ProfileStore';

type JsonObj = Record<string, Object>;

/** Xray JSON 配置与 VPN VpnConfig 生成（对应 v2rayNG CoreConfigManager 精简版） */
export class ConfigBuilder {
  /** 生成 VPN 虚拟网卡配置（对应 CoreVpnService.configureNetworkSettings） */
  static buildVpnConfig(mtu: number, excludedBundle: string): vpnExtension.VpnConfig {
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
      // 虚拟 DNS 的 UDP 查询由 socks 入站路由到 Xray dns-out，而非直接发公网 UDP。
      dnsAddresses: ['10.111.222.2'],
      isIPv4Accepted: true,
      isIPv6Accepted: false,
      isBlocking: false,
      isInternal: false,
      blockedApplications: [excludedBundle]
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
  static buildXrayConfig(p: Profile, st: XraySettings, hasGeo: boolean, filesDir: string): string {
    let proxy: JsonObj | null = ConfigBuilder.buildProxyOutbound(p);
    if (proxy === null) {
      throw new Error('节点协议不受支持，拒绝退化为直连');
    }
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
    // Xray 26.7.28 的 DNS 出站将 A/AAAA 请求交给内置 DNS，返回给 TUN 调用者。
    let dnsSettings: JsonObj = {};
    let dnsOutbound: JsonObj = { 'tag': 'dns-out', 'protocol': 'dns', 'settings': dnsSettings };
    outbounds.push(dnsOutbound);

    let socksSettings: JsonObj = { 'udp': true, 'auth': 'noauth' };
    let socksInbound: JsonObj = {
      'tag': 'socks', 'port': 10808, 'listen': '127.0.0.1',
      'protocol': 'socks', 'settings': socksSettings
    };
    // FakeDNS 依赖嗅探把假 IP 还原成真实域名（v2rayNG 同款机制），因此嗅探必须常开。
    let destOverride: Array<string> = ['fakedns', 'http', 'tls', 'quic'];
    let sniffing: JsonObj = { 'enabled': true, 'destOverride': destOverride };
    socksInbound['sniffing'] = sniffing;
    let inbounds: Array<Object> = [socksInbound];

    // 路由规则（对应 v2rayNG routing）。
    // hasGeo=false（尚未下载 geoip/geosite.dat）时不引用 geo 规则，
    // 改用 CIDR 直连私有地址，保证 Xray 能启动、全局代理可用。
    let rules: Array<Object> = [];
    // 必须在私有地址直连规则之前捕获虚拟 DNS 的 53 端口，避免把它直连到物理网络。
    let socksTags: Array<string> = ['socks'];
    let dnsRule: JsonObj = { 'type': 'field', 'inboundTag': socksTags, 'port': '53', 'outboundTag': 'dns-out' };
    rules.push(dnsRule);
    let dnsTags: Array<string> = ['dns-internal'];
    let dnsTransportRule: JsonObj = { 'type': 'field', 'inboundTag': dnsTags, 'outboundTag': 'proxy' };
    rules.push(dnsTransportRule);
    let privateIps: Array<string> = hasGeo
      ? ['geoip:private']
      : ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8',
         '169.254.0.0/16', '224.0.0.0/4', '255.255.255.255/32'];
    let privateRule: JsonObj = { 'type': 'field', 'ip': privateIps, 'outboundTag': 'direct' };
    rules.push(privateRule);
    if (hasGeo && st.blockAds) {
      let adDomains: Array<string> = ['geosite:category-ads-all'];
      let adRule: JsonObj = { 'type': 'field', 'domain': adDomains, 'outboundTag': 'block' };
      rules.push(adRule);
    }
    if (hasGeo && st.routeMode === 1) {
      let cnIps: Array<string> = ['geoip:cn'];
      let cnIpRule: JsonObj = { 'type': 'field', 'ip': cnIps, 'outboundTag': 'direct' };
      rules.push(cnIpRule);
      let cnDomains: Array<string> = ['geosite:cn'];
      let cnDomainRule: JsonObj = { 'type': 'field', 'domain': cnDomains, 'outboundTag': 'direct' };
      rules.push(cnDomainRule);
    }
    let routing: JsonObj = { 'domainStrategy': 'IPIfNonMatch', 'rules': rules };
    let log: JsonObj = { 'loglevel': st.logLevel, 'error': filesDir + '/xray-error.log' };
    // A/AAAA 查询由 FakeDNS 本地应答，不出网；上游仅兜底处理其他记录类型。
    // 上游用 UDP：真机日志显示 tcp://1.1.1.1 直连被持续重置（closed pipe 刷屏）。
    let dnsServers: Array<string> = ['1.1.1.1', '8.8.8.8'];
    // FakeDNS：虚拟 DNS 的 A/AAAA 查询由本地假 IP 池应答，不出网；
    // 真实域名在后续连接里经嗅探还原后交给代理端解析。
    // 真机日志显示上游 tcp://1.1.1.1 直连被重置（app/dns closed pipe），FakeDNS 可彻底绕开。
    let fakeDns: Array<JsonObj> = [{ 'ipPool': '198.18.0.0/15', 'poolSize': 10000 }];
    let dns: JsonObj = { 'servers': dnsServers, 'tag': 'dns-internal', 'queryStrategy': 'UseIPv4', 'fakedns': fakeDns };

    let config: JsonObj = {
      'log': log, 'dns': dns, 'inbounds': inbounds, 'outbounds': outbounds, 'routing': routing
    };
    return JSON.stringify(config);
  }
}

