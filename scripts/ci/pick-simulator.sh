#!/bin/bash
# Print the UDID of an existing iPhone simulator on the newest installed iOS runtime.
# Uses SIMULATOR_UDID if set. Never creates a device.

set -euo pipefail

if [ -n "${SIMULATOR_UDID:-}" ]; then
    echo "$SIMULATOR_UDID"
    exit 0
fi

xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else None
runtimes = sorted((r for r in devices if version(r)), key=version, reverse=True)
for runtime in runtimes:
    phones = [d for d in devices[runtime] if d.get("isAvailable") and d["name"].startswith("iPhone")]
    # Prefer a Pro model, then any iPhone.
    phones.sort(key=lambda d: ("Pro" not in d["name"], d["name"]))
    if phones:
        print(phones[0]["udid"])
        print(phones[0]["name"], runtime, file=sys.stderr)
        sys.exit(0)
sys.exit("No available iPhone simulator found")
'
