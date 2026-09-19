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

# The simulator booting since before the build (Scripts/boot-simulator.sh), or one picked now.
UDID="${SIMULATOR_UDID:-}"
if [ -z "$UDID" ]; then
  UDID=$("$(dirname "$0")/boot-simulator.sh" | tail -n 1)
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
booting=$SECONDS
xcrun simctl bootstatus "$UDID" -b >/dev/null
BOOT_WAIT=$((SECONDS - booting))
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
  for _ in $(seq 1 "${2:-225}"); do
    [ -f "$marker" ] && return 0
    sleep 0.2
  done
  return 1
}

# The override stays until the simulator shuts down: once is enough.
override_status_bar
# Installing creates the app's folder; it's asked for again after the first launch otherwise.
DATA_DIR=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)

# No separate warm-up: the first launch after installing is slow, so the first scene simply gets
# more time to report ready.
TIMINGS=""
CAPTURE_STARTED=$SECONDS
patience=600
for scene in "${CHOSEN[@]}"; do
  if [ -n "$DATA_DIR" ]; then
    rm -f "$DATA_DIR/tmp/OCTODemoReady"
  fi
  started=$SECONDS
  launch "$scene"
  launched=$SECONDS
  if [ -z "$DATA_DIR" ]; then
    DATA_DIR=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
  fi
  if wait_until_ready "$DATA_DIR" "$patience"; then
    sleep 0.3
  else
    echo "::warning title=Screenshots::The $scene scene did not report ready after $((patience / 5)) s"
    xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -i octo | sed 's/^/::warning title=launchctl::/' || true
  fi
  ready=$SECONDS
  xcrun simctl io "$UDID" screenshot --type=png "$OUTPUT_DIR/$scene.png" >/dev/null
  # Launch, until ready, screenshot.
  TIMINGS="$TIMINGS $scene $((SECONDS - started))s ($((launched - started))+$((ready - launched))+$((SECONDS - ready)))"
  echo "Captured $scene in $((SECONDS - started)) s"
  patience=225
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
# One annotation for the whole run: the API keeps it, unlike the log.
echo "::notice title=Screenshot timings::${#CHOSEN[@]} scenes in $((SECONDS - CAPTURE_STARTED)) s, after waiting $BOOT_WAIT s for the simulator:$TIMINGS"
