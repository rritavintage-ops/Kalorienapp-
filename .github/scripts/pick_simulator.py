#!/usr/bin/env python3
"""Prints the UDID of the best available iPhone simulator for the selected Xcode's SDK."""
import json
import re
import subprocess
import sys

sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()
sdk_version = tuple(int(part) for part in sdk.split(".")[:2])
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]

candidates = []
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    if version > sdk_version:
        continue
    for device in entries:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        if re.fullmatch(r"iPhone \d+ Pro", name):
            score = 3
        elif re.fullmatch(r"iPhone \d+", name):
            score = 2
        elif "SE" in name:
            score = 0
        else:
            score = 1
        candidates.append((version, score, name, device["udid"]))

if not candidates:
    sys.exit(f"No iPhone simulator found for iOS SDK {sdk}")

candidates.sort(reverse=True)
version, _, name, udid = candidates[0]
print(f"Using {name} (iOS {version[0]}.{version[1]}, SDK {sdk})", file=sys.stderr)
print(udid)
