#!/usr/bin/env bash
# Captures OCTO's demo scenes on an iOS simulator.
# Usage: Scripts/take-screenshots.sh <OCTO.app built with OCTO_DEMO> <output directory>
set -euo pipefail

APP_PATH="$1"
OUTPUT_DIR="$2"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
LANGUAGE="${SCREENSHOT_LANGUAGE:-fr}"
LOCALE_ID="${SCREENSHOT_LOCALE:-fr_FR}"
BUNDLE_ID="com.gabrielb0x.octo"
SCENES=(welcome home chat sidebar voice settings)

UDID=$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
name = sys.argv[1]
matches = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in re.findall(r"\d+", runtime.split(".iOS-")[-1]))
    matches += [(version, device["udid"]) for device in devices if device["name"] == name]
if not matches:
    sys.exit("No available simulator named " + name)
print(max(matches)[1])
' "$DEVICE_NAME")

echo "Using $DEVICE_NAME ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark
xcrun simctl install "$UDID" "$APP_PATH"
mkdir -p "$OUTPUT_DIR"

override_status_bar() {
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState discharging --batteryLevel 100
}

launch() {
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    -OCTODemoScene "$1" \
    -AppleLanguages "($LANGUAGE)" \
    -AppleLocale "$LOCALE_ID" >/dev/null
}

# In demo builds the app creates tmp/OCTODemoReady once the scene is fully on screen.
wait_until_ready() {
  local marker="$1/tmp/OCTODemoReady"
  for _ in $(seq 1 90); do
    [ -f "$marker" ] && return 0
    sleep 0.5
  done
  return 1
}

# The first launch after installing is slow, so warm up before capturing.
launch home
DATA_DIR=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
wait_until_ready "$DATA_DIR" || echo "::warning title=Screenshots::Warm-up launch never reported ready"

for scene in "${SCENES[@]}"; do
  override_status_bar
  rm -f "$DATA_DIR/tmp/OCTODemoReady"
  started=$SECONDS
  launch "$scene"
  if wait_until_ready "$DATA_DIR"; then
    echo "$scene ready after $((SECONDS - started)) s"
    sleep 1
  else
    echo "::warning title=Screenshots::The $scene scene did not report ready after 45 s"
    xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -i octo | sed 's/^/::warning title=launchctl::/' || true
  fi
  xcrun simctl io "$UDID" screenshot --type=png "$OUTPUT_DIR/$scene.png"
  echo "Captured $scene"
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
