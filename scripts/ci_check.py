#!/usr/bin/env python3
"""CI structure & syntax check for the V2rayNG HarmonyOS port.

Verifies: required files exist, all .json5/.json parse, the VPN extension and
INTERNET permission are declared, and every page is registered for routing.
"""
import json
import sys
from pathlib import Path

import json5

ROOT = Path(__file__).resolve().parent.parent

REQUIRED = [
    "AppScope/app.json5",
    "build-profile.json5",
    "hvigorfile.ts",
    "oh-package.json5",
    "entry/build-profile.json5",
    "entry/hvigorfile.ts",
    "entry/oh-package.json5",
    "entry/src/main/module.json5",
    "entry/src/main/profile/main_pages.json",
    "entry/src/main/ets/entryability/EntryAbility.ets",
    "entry/src/main/ets/vpnability/VpnTunnelAbility.ets",
    "entry/src/main/ets/core/ConfigBuilder.ets",
    "entry/src/main/ets/core/ProfileStore.ets",
    "entry/src/main/ets/core/VpnController.ets",
    "entry/src/main/ets/model/Profile.ets",
    "entry/src/main/ets/native/libxray.ets",
    "entry/src/main/ets/pages/Index.ets",
    "entry/src/main/ets/pages/ServerEdit.ets",
    "entry/src/main/cpp/CMakeLists.txt",
    "entry/src/main/cpp/napi_init.cpp",
]

errors = []

for rel in REQUIRED:
    if not (ROOT / rel).is_file():
        errors.append(f"missing file: {rel}")

for p in sorted(ROOT.rglob("*.json5")):
    if ".git" in p.parts:
        continue
    try:
        json5.loads(p.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        errors.append(f"invalid json5: {p.relative_to(ROOT)}: {e}")

for p in sorted(ROOT.rglob("*.json")):
    if ".git" in p.parts:
        continue
    try:
        json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        errors.append(f"invalid json: {p.relative_to(ROOT)}: {e}")

module_path = ROOT / "entry/src/main/module.json5"
if module_path.is_file():
    module = json5.loads(module_path.read_text(encoding="utf-8")).get("module", {})
    extensions = module.get("extensionAbilities", [])
    if not any(e.get("type") == "vpn" for e in extensions):
        errors.append("module.json5: no extensionAbility with type 'vpn'")
    vpn_entries = [e for e in extensions if e.get("type") == "vpn"]
    for e in vpn_entries:
        src = e.get("srcEntry", "")
        if not (ROOT / "entry/src/main" / src.lstrip("./")).is_file():
            errors.append(f"module.json5: vpn srcEntry not found: {src}")
    perms = [perm.get("name") for perm in module.get("requestPermissions", [])]
    if "ohos.permission.INTERNET" not in perms:
        errors.append("module.json5: ohos.permission.INTERNET not declared")

pages_path = ROOT / "entry/src/main/profile/main_pages.json"
if pages_path.is_file():
    try:
        pages = json.loads(pages_path.read_text(encoding="utf-8")).get("src", [])
        for page in ("pages/Index", "pages/ServerEdit"):
            if page not in pages:
                errors.append(f"main_pages.json: {page} not registered")
    except Exception as e:  # noqa: BLE001
        errors.append(f"main_pages.json unreadable: {e}")

if errors:
    for e in errors:
        print(f"FAIL: {e}")
    sys.exit(1)

print(f"OK: {len(REQUIRED)} required files present, json5/json valid, vpn extension + INTERNET permission declared")
