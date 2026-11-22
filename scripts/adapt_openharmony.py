#!/usr/bin/env python3
"""Temporarily retarget the project from HarmonyOS to OpenHarmony so that the
open-source OpenHarmony SDK + hvigor 4.x can build it in CI.

Changes (in-memory / working tree only, never committed):
  1. runtimeOS: HarmonyOS      -> OpenHarmony
  2. compatibleSdkVersion 5.0.0(12) -> compileSdkVersion/compatibleSdkVersion: 12
  3. drop buildOption.strictMode (not in the hvigor 4.x schema)
"""
import re
from pathlib import Path

p = Path(__file__).resolve().parent.parent / 'build-profile.json5'
s = p.read_text(encoding='utf-8')
s = s.replace('"compatibleSdkVersion": "5.0.0(12)",',
              '"compileSdkVersion": 12,\n        "compatibleSdkVersion": 12,')
s = s.replace('"runtimeOS": "HarmonyOS"', '"runtimeOS": "OpenHarmony"')
s = re.sub(r'"buildOption": \{\s*"strictMode": \{[^}]*\}\s*\},?', '', s)
p.write_text(s, encoding='utf-8')
print(s)
