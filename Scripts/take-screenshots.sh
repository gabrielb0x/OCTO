#!/usr/bin/env bash
# Captures OCTO's demo scenes on an iOS simulator.
# Usage: SCENES="readme" Scripts/take-screenshots.sh <OCTO.app built with OCTO_DEMO> <output directory>
#
# SCENES picks what to capture: "readme" (the six screens of the README, the default), "all",
# or scene names, separated by spaces or commas — e.g. SCENES="readme usage telemetry".
set -euo pipefail

APP_PATH="$1"
OUTPUT_DIR="$2"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
LANGUAGE="${SCREENSHOT_LANGUAGE:-fr}"
LOCALE_ID="${SCREENSHOT_LOCALE:-fr_FR}"
BUNDLE_ID="com.gabrielb0x.octo"
ALL_SCENES=(welcome home chat sidebar voice settings settingsApp subscription upgrade about developer network deleteToast freePlan lightChat messageDetails whatsNew appearance privacy dataControls ageVerification devices storage memory update accounts ads tabs tabsChats layout models usage editProfile scrollButton telemetry)
README_SCENES=(home chat sidebar tabsChats voice settings)

# The scenes asked for, each once, in the order asked. Unknown names are reported and skipped.
CHOSEN=()
add_scene() {
  local scene
  for scene in ${CHOSEN[@]+"${CHOSEN[@]}"}; do
    [ "$scene" = "$1" ] && return 0
  done
  CHOSEN+=("$1")
}
for word in $(printf '%s' "${SCENES:-readme}" | tr ',' ' '); do
  case "$word" in
    all) for scene in "${ALL_SCENES[@]}"; do add_scene "$scene"; done ;;
    readme) for scene in "${README_SCENES[@]}"; do add_scene "$scene"; done ;;
    *)
      if printf '%s\n' "${ALL_SCENES[@]}" | grep -qx -- "$word"; then
        add_scene "$word"
      else
        echo "::warning title=Screenshots::Unknown scene $word"
      fi
      ;;
  esac
done
if [ ${#CHOSEN[@]} -eq 0 ]; then
  CHOSEN=("${README_SCENES[@]}")
fi
echo "Capturing ${#CHOSEN[@]} scenes: ${CHOSEN[*]}"

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

# Replaces the app still running from the previous scene in a single call.
launch() {
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" \
    -OCTODemoScene "$1" \
    -AppleLanguages "($LANGUAGE)" \
    -AppleLocale "$LOCALE_ID" >/dev/null
}

# In demo builds the app creates tmp/OCTODemoReady once the scene has settled: each scene waits
# as long as what it opens needs (`DemoContent.settleTime`), so this only has to notice it.
wait_until_ready() {
  local marker="$1/tmp/OCTODemoReady"
  for _ in $(seq 1 225); do
    [ -f "$marker" ] && return 0
    sleep 0.2
  done
  return 1
}

# The override stays until the simulator shuts down: once is enough.
override_status_bar

# The first launch after installing is slow, so warm up before capturing.
launch home
DATA_DIR=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
wait_until_ready "$DATA_DIR" || echo "::warning title=Screenshots::Warm-up launch never reported ready"

TIMINGS=""
CAPTURE_STARTED=$SECONDS
for scene in "${CHOSEN[@]}"; do
  rm -f "$DATA_DIR/tmp/OCTODemoReady"
  started=$SECONDS
  launch "$scene"
  if wait_until_ready "$DATA_DIR"; then
    sleep 0.3
  else
    echo "::warning title=Screenshots::The $scene scene did not report ready after 45 s"
    xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -i octo | sed 's/^/::warning title=launchctl::/' || true
  fi
  xcrun simctl io "$UDID" screenshot --type=png "$OUTPUT_DIR/$scene.png" >/dev/null
  TIMINGS="$TIMINGS $scene $((SECONDS - started))s"
  echo "Captured $scene in $((SECONDS - started)) s"
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
# One annotation for the whole run: the API keeps it, unlike the log.
echo "::notice title=Screenshot timings::${#CHOSEN[@]} scenes in $((SECONDS - CAPTURE_STARTED)) s:$TIMINGS"
