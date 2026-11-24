#!/usr/bin/env python3
"""源码契约回归 + 对实际 C++ SOCKS 读取实现的分包/超时测试。
不连接公网，不需要节点凭据；不把 CI 测试当作真机 VPN 联网证明。
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
ETS = ROOT / 'entry/src/main/ets'

class Contracts(unittest.TestCase):
    def test_ui_uses_vpn_snapshot(self):
        page = (ETS / 'pages/Index.ets').read_text()
        self.assertIn('RuntimeStore.read(context)', page)
        self.assertIn('isRuntimeRunning(state)', page)
        self.assertNotIn("@StorageProp('vpnRunning')", page)
        self.assertIn('this.startStateReader()', page)
        self.assertIn("'断开 VPN'", page)

    def test_logs_never_load_ui_core(self):
        page = (ETS / 'pages/Logs.ets').read_text()
        self.assertNotIn('LibXray', page)
        self.assertIn('RuntimeStore.read(context)', page)
        self.assertIn('tunTxBytes', page)
        self.assertIn('tunRxBytes', page)
        self.assertIn('不包含 TUN 和系统 DNS', page)

    def test_atomic_runtime_not_handmade_json(self):
        text = (ETS / 'core/RuntimeStore.ets').read_text()
        self.assertIn('JSON.stringify(snapshot)', text)
        # 多副本轮换写入：每份仍走 tmp + rename 的原子替换。
        self.assertIn('fs.renameSync(temporary, targets[i])', text)
        self.assertIn("dir + '/vpn-runtime-' + slot + '.json'", text)
        self.assertIn('encoded.byteOffset', text)
        ability = (ETS / 'vpnability/VpnTunnelAbility.ets').read_text()
        self.assertNotIn('diag.json', ability)
        self.assertNotIn("writeDiag('selftest'", ability)
        self.assertIn('this.snapshot.state = \'running\'', ability)
        self.assertIn('this.snapshot.native.hevExited', ability)
        self.assertIn('await conn.destroy()', ability)

    def test_full_config_snapshot_in_want(self):
        text = (ETS / 'core/VpnController.ets').read_text()
        self.assertIn("'profileJson': JSON.stringify(profile)", text)
        self.assertIn("'settingsJson': JSON.stringify(settings)", text)
        self.assertNotIn("setOrCreate('vpnRunning', true)", text)

    def test_no_self_vpn_loop(self):
        text = (ETS / 'core/ConfigBuilder.ets').read_text()
        self.assertIn('blockedApplications: [excludedBundle]', text)
        self.assertNotIn('trustedApplications:', text)
        self.assertIn('this.snapshot.excludedBundle = BUNDLE_NAME', (ETS / 'vpnability/VpnTunnelAbility.ets').read_text())

    def test_dns_is_explicitly_intercepted_before_private_bypass(self):
        text = (ETS / 'core/ConfigBuilder.ets').read_text()
        self.assertIn("dnsAddresses: ['10.111.222.2']", text)
        self.assertIn("'protocol': 'dns'", text)
        self.assertLess(text.index('rules.push(dnsRule)'), text.index('rules.push(privateRule)'))
        # FakeDNS 本地应答 A/AAAA；上游仅兜底其他记录类型（UDP，避免 TCP 直连被重置）。
        self.assertIn("'fakedns'", text)
        self.assertIn("'1.1.1.1'", text)
        self.assertIn("'queryStrategy': 'UseIPv4'", text)

    def test_semver_does_not_offer_downgrade(self):
        node = shutil.which('node')
        if not node:
            self.skipTest('本地没有 Node；GitHub runner 上执行')
        # 此模块仅有基本 TS 类型标注；移除标注后运行同一函数，不复制其算法。
        source = (ETS / 'core/UpdateVersion.ets').read_text()
        source = source.replace('export function', 'function')
        source = re.sub(r':\s*RegExpMatchArray\s*\|\s*null', '', source)
        source = re.sub(r':\s*(string|number|boolean)\b', '', source)
        cases = [('1.3.2','v1.3.1',False), ('1.3.2','v1.3.2',False),
                 ('1.3.2','v1.3.3',True), ('1.9.9','v1.10.0',True),
                 ('1.3.2-rc.1','v1.3.2',True), ('1.3.2','v1.3.2-rc.1',False)]
        source += '\nconst cases=' + json.dumps(cases) + ';\n'
        source += 'for (const [a,b,want] of cases) { if (isNewerVersion(a,b)!==want) throw Error(a+" -> "+b); }'
        result = subprocess.run([node, '-e', source], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cpp_actual_fragmented_reply_reader(self):
        compiler = shutil.which('g++')
        if not compiler:
            if os.environ.get('CI') == 'true':
                self.fail('CI 缺少 g++，不能跳过 native 回归')
            self.skipTest('本地没有 native 编译器；GitHub runner 上执行')
        cpp = (ROOT / 'entry/src/main/cpp/napi_init.cpp').read_text()
        start = cpp.index('static long long NowMs()')
        end = cpp.index('static void SetProbe', start)
        functions = cpp[start:end]
        harness = '''
#include <sys/socket.h>
#include <poll.h>
#include <unistd.h>
#include <atomic>
#include <chrono>
#include <thread>
#include <vector>
#include <algorithm>
#include <cerrno>
#include <cassert>
static std::atomic_bool g_stopping(false);
'''+functions+'''
static void check(std::vector<unsigned char> packet, bool want) {
  int fd[2]; assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fd) == 0);
  std::thread writer([&]() {
    for (auto c: packet) { send(fd[1], &c, 1, MSG_NOSIGNAL); usleep(2000); }
    close(fd[1]);
  });
  bool ok=ReadSocksReply(fd[0], NowMs()+1000);
  assert(ok==want); close(fd[0]); writer.join();
}
int main() {
  check({5,0,0,1,1,2,3,4,0,80}, true);
  check({5,0,0,3,2,'o','k',0,80}, true);
  std::vector<unsigned char> v6(22); v6[0]=5; v6[3]=4; check(v6,true);
  check({5,1,0,1,0,0,0,0,0,0},false);
  check({5,0,0,9},false);
  int fd[2]; assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fd)==0);
  assert(!ReadSocksReply(fd[0],NowMs()+50));
  g_stopping.store(true); assert(!ReadSocksReply(fd[0],NowMs()+1000));
  close(fd[0]); close(fd[1]);
}
'''
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'probe_test.cpp'
            executable = Path(directory) / 'probe_test'
            source.write_text(harness)
            result = subprocess.run([compiler, '-std=c++17', '-pthread', str(source), '-o', str(executable)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)

if __name__ == '__main__':
    unittest.main(verbosity=2)
