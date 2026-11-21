#!/usr/bin/env python3
"""Prints downscaled UI-test screenshots as base64 blocks in the job log.

Useful when artifacts can't be downloaded: extract with
`sed -n '/SCREENSHOT_BEGIN/,/SCREENSHOT_END/p'` from the log and base64-decode each block.
"""
import base64
import json
import os
import subprocess
import sys
import tempfile

root = sys.argv[1]
names = {}
manifest = os.path.join(root, "manifest.json")
if os.path.exists(manifest):
    def walk(node):
        if isinstance(node, dict):
            if "exportedFileName" in node:
                names[node["exportedFileName"]] = node.get("suggestedHumanReadableName", node["exportedFileName"])
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
    with open(manifest) as handle:
        walk(json.load(handle))

files = [f for f in os.listdir(root) if f.lower().endswith((".png", ".jpg", ".jpeg"))]
for name in sorted(files, key=lambda f: names.get(f, f)):
    output = os.path.join(tempfile.gettempdir(), "screenshot.jpg")
    subprocess.run(
        ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "60", "--resampleWidth", "430",
         os.path.join(root, name), "--out", output],
        check=True, capture_output=True,
    )
    with open(output, "rb") as handle:
        encoded = base64.b64encode(handle.read()).decode()
    print(f"SCREENSHOT_BEGIN {names.get(name, name)}")
    for start in range(0, len(encoded), 2000):
        print(encoded[start:start + 2000])
    print("SCREENSHOT_END")
