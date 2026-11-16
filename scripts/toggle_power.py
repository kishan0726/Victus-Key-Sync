#!/usr/bin/env python3
import json, os, tempfile

d = os.path.expanduser("~/.config/victus-sync")
p = f"{d}/state.json"
try:
    with open(p) as f:
        state = json.load(f)
except (OSError, ValueError):
    state = {}
state["power"] = not state.get("power", True)
os.makedirs(d, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=d)   # write a temp file, then rename: no half-written reads
with os.fdopen(fd, "w") as f:
    json.dump(state, f)
os.replace(tmp, p)
print("power:", "on" if state["power"] else "off")
