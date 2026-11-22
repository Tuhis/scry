#!/usr/bin/env python3
"""Runs INSIDE the simulator container (see tools/docker/sim.Dockerfile). Use ./dev sim.

Loads /addons/<Addon> into wowless and condenses its very verbose log into:
did the addon load, what did it print, and which Lua errors involve the addon.
"""
import os
import re
import subprocess
import sys

ADDON = sys.argv[1] if len(sys.argv) > 1 else "Scry"
PRODUCT = os.environ.get("WOWLESS_PRODUCT", "wow")
OUT = "/tmp/wowless-out.txt"
STAMP = re.compile(r"^\[\d+\.\d+\] ")

proc = subprocess.run(
    [f"build/wowless_{PRODUCT}", "run", "-p", PRODUCT, "-l", "3", "-a", f"/addons/{ADDON}", "-o", OUT],
    cwd="/wowless", stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
)

blocks, current = [], None
loaded_files, done_loading, chat = 0, False, []
with open(OUT, errors="replace") as f:
    for line in f:
        line = line.rstrip("\n")
        if STAMP.match(line):
            body = STAMP.sub("", line)
            current = None
            if body.startswith("error: "):
                current = [body]
                blocks.append(current)
            elif body.startswith(f"loading file /addons/{ADDON}/"):
                loaded_files += 1
            elif body == f"done loading {ADDON}":
                done_loading = True
            elif body.startswith("[ChatFrame") and ADDON.lower() in body.lower():
                chat.append(body)
        elif current is not None:
            current.append(line)

marker = f"addons\\{ADDON}\\"
ours = [b for b in blocks if any(marker in line for line in b)]
theirs = [b for b in blocks if b not in ours]

print(f"simulator: wowless, product {PRODUCT} (real Blizzard UI code, stubbed game data)")
if not done_loading:
    print(f"FAIL  addon was not loaded (simulator exit code {proc.returncode})")
    print(proc.stdout[-3000:])
    sys.exit(1)
print(f"ok    addon loaded ({loaded_files} files), login events fired, UI exercised")
if chat:
    print(f"chat lines mentioning {ADDON} ({len(chat)}, first 30):")
    for line in chat[:30]:
        print("      " + line)
if theirs:
    print(f"note  {len(theirs)} error(s) not involving the addon (simulator gaps, ignore):")
    for b in theirs[:5]:
        print("      " + b[0][:200])
if ours:
    print(f"FAIL  {len(ours)} Lua error(s) involving the addon:")
    for b in ours:
        print("      " + b[0])
        for line in [l for l in b[1:] if marker in l][:8]:
            print("        " + line.strip())
    print("\nSIM FAILED")
    sys.exit(1)
print("\nSIM PASSED")
