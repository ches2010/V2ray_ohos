#!/usr/bin/env python3
"""检查交付 HAP 的内部版本与 native 标记，防止把旧包改名当成新包。
Usage: python3 scripts/verify_hap.py file.hap
"""
import hashlib
import json
import sys
import zipfile
from pathlib import Path

path = Path(sys.argv[1])
with zipfile.ZipFile(path) as hap:
    required = ['module.json', 'pack.info', 'ets/modules.abc',
                'libs/arm64-v8a/libentry.so', 'libs/arm64-v8a/libxray.so',
                'libs/arm64-v8a/libhevsocks5tun.so']
    for name in required:
        if name not in hap.namelist():
            raise SystemExit('FAIL missing: '+name)
    if hap.testzip() is not None:
        raise SystemExit('FAIL HAP CRC')
    pack = json.loads(hap.read('pack.info'))
    version = pack['summary']['app']['version']['name']
    expected = json.loads((Path(__file__).parent.parent / 'AppScope/app.json5').read_text())['app']['versionName']
    if version != expected:
        raise SystemExit('FAIL version: '+version+' != '+expected)
    signature = b'vpn-runtime-v2-self-excluded'
    if signature not in hap.read('libs/arm64-v8a/libentry.so'):
        raise SystemExit('FAIL old native bridge: build signature absent')
    result = {'file': path.name, 'versionName': version, 'buildSignature': signature.decode(),
              'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'nativeLibraries': {name: hap.getinfo(name).file_size for name in required if name.endswith('.so')}}
print(json.dumps(result, ensure_ascii=False, indent=2))
