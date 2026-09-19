#!/usr/bin/env bash
# Picks the iPhone simulator of the screenshots — creating it when the runner image doesn't ship
# one — and starts booting it without waiting for the boot to finish.
# Prints the device's UDID on its last line, and exports it as SIMULATOR_UDID on GitHub Actions.
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"

# GitHub keeps 10 annotations per step: list iOS runtimes only so readiness warnings stay visible.
xcrun simctl list runtimes available | grep "^iOS" | sed 's/^/::notice title=Simulator runtimes::/' || true

# Uses the device on the newest installed iOS runtime, creating it when the image doesn't ship one.
UDID=$(python3 - "$DEVICE_NAME" <<'PY'
import json, re, subprocess, sys

name = sys.argv[1]
simctl = json.loads(subprocess.run(["xcrun", "simctl", "list", "--json"], check=True, capture_output=True, text=True).stdout)

def version(identifier):
    return tuple(int(part) for part in re.findall(r"\d+", identifier.split(".iOS-")[-1]))

runtimes = sorted(
    (runtime["identifier"] for runtime in simctl["runtimes"] if runtime.get("isAvailable") and ".iOS-" in runtime["identifier"]),
    key=version,
)
if not runtimes:
    sys.exit("No iOS simulator runtime is installed")
runtime = runtimes[-1]

for device in simctl["devices"].get(runtime, []):
    if device["name"] == name and device.get("isAvailable"):
        print(device["udid"])
        sys.exit()

device_types = [kind for kind in simctl["devicetypes"] if kind["name"] == name]
device_types = device_types or [kind for kind in simctl["devicetypes"] if kind["name"].startswith("iPhone") and kind["name"].endswith(" Pro")]
if not device_types:
    sys.exit("No iPhone simulator type is available")
created = subprocess.run(["xcrun", "simctl", "create", "OCTO " + device_types[-1]["name"], device_types[-1]["identifier"], runtime], check=True, capture_output=True, text=True)
print(created.stdout.strip())
PY
) || { echo "::error title=Screenshots::Could not find or create a $DEVICE_NAME simulator"; exit 1; }

echo "::notice title=Simulator::$(xcrun simctl list devices | grep "$UDID" | sed -E 's/^ +//')"

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "SIMULATOR_UDID=$UDID" >> "$GITHUB_ENV"
fi
echo "$UDID"
