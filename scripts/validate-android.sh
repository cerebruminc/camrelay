#!/bin/sh
# End-to-end Android check. Owns the relay, emulator, and validation app.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"

AVD=${1:-}
if [ -z "$AVD" ]; then
  echo "Usage: $0 <avd-name>" >&2
  exit 2
fi

SDK_ROOT=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}
ADB="$SDK_ROOT/platform-tools/adb"
APP_ID=org.camrelay.expo
APK=Examples/CamRelayExpo/android/app/build/outputs/apk/release/app-release.apk

command -v jq >/dev/null
command -v magick >/dev/null
command -v rg >/dev/null
command -v xmllint >/dev/null
test -x "$ADB"
test -x .build/debug/camrelay
test -f "$APK"
for fixture in checkerboard.png colors.mp4 orientation.png orientation-rotate90.mp4; do
  test -f ".build/fixtures/$fixture"
done

mkdir -p .build/validation
RUN_DIR=$(mktemp -d "$PROJECT_DIR/.build/validation/android.XXXXXX")
SESSION="android-validation-$$"
RELAY_PID=
SERIAL=

AVD_HOME=${ANDROID_AVD_HOME:-$HOME/.android/avd}
AVD_INI="$AVD_HOME/$AVD.ini"
test -f "$AVD_INI"
AVD_DIRECTORY=$(sed -n 's/^path=//p' "$AVD_INI" | head -1)
test -d "$AVD_DIRECTORY"
ENVIRONMENT_FILE="$AVD_DIRECTORY/environment.ini"
ORIGINAL_ENVIRONMENT=missing
ORIGINAL_PERMISSIONS=
if [ -f "$ENVIRONMENT_FILE" ]; then
  ORIGINAL_ENVIRONMENT=$(shasum -a 256 "$ENVIRONMENT_FILE" | awk '{print $1}')
  ORIGINAL_PERMISSIONS=$(stat -f '%Lp' "$ENVIRONMENT_FILE")
fi

control() { .build/debug/camrelay "$@" --session "$SESSION"; }

cleanup() {
  if [ -n "$RELAY_PID" ]; then
    control stop >/dev/null 2>&1 || kill -TERM "$RELAY_PID" 2>/dev/null || true
    wait "$RELAY_PID" 2>/dev/null || true
  fi
  echo "Validation artifacts: $RUN_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

dump_ui() {
  "$ADB" -s "$SERIAL" shell uiautomator dump /sdcard/camrelay-window.xml >/dev/null 2>&1 &&
    "$ADB" -s "$SERIAL" exec-out cat /sdcard/camrelay-window.xml >"$RUN_DIR/window.xml" 2>/dev/null
}

await_ui() {
  pattern=$1
  attempts=0
  until dump_ui && rg -q "$pattern" "$RUN_DIR/window.xml"; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 120 ]; then
      echo "Timed out waiting for app UI: $pattern" >&2
      tail -c 2000 "$RUN_DIR/window.xml" >&2 || true
      return 1
    fi
    sleep 0.5
  done
}

await_camera() {
  attempts=0
  until dump_ui && rg -q 'Camera: active|No camera available' "$RUN_DIR/window.xml"; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 60 ]; then
      echo "Timed out waiting for the app to inspect Android cameras." >&2
      return 1
    fi
    sleep 0.5
  done

  # A fresh install can cache the empty camera list in its first process.
  if rg -q 'No camera available' "$RUN_DIR/window.xml"; then
    "$ADB" -s "$SERIAL" shell am force-stop "$APP_ID"
    "$ADB" -s "$SERIAL" shell am start -W -n "$APP_ID/.MainActivity" >/dev/null
  fi

  await_ui 'Camera: active'
  await_ui 'Preview: active'
}

open_action() {
  "$ADB" -s "$SERIAL" shell am start -W -a android.intent.action.VIEW \
    -d "org.camrelay.expo://$1" "$APP_ID" >/dev/null
}

preview_bounds() {
  dump_ui
  bounds=$(xmllint --xpath \
    'string(//node[contains(@resource-id,"camera-preview")]/@bounds)' \
    "$RUN_DIR/window.xml")
  set -- $(printf '%s' "$bounds" | tr '[],' '   ')
  if [ "$#" -ne 4 ]; then
    echo "Could not locate the camera preview bounds." >&2
    return 1
  fi
  printf '%s %s %s %s\n' "$1" "$2" "$3" "$4"
}

pixel_color() {
  file=$1
  x=$2
  y=$3
  magick "$file" -format \
    "%[fx:round(255*p{$x,$y}.r)] %[fx:round(255*p{$x,$y}.g)] %[fx:round(255*p{$x,$y}.b)]" \
    info: | awk '{
      if ($1 > 150 && $2 < 100 && $3 < 100) print "R"
      else if ($2 > 150 && $1 < 100 && $3 < 100) print "G"
      else if ($3 > 150 && $1 < 100 && $2 < 100) print "B"
      else if ($1 > 150 && $2 > 150 && $3 < 100) print "Y"
      else print "?"
    }'
}

preview_signature() {
  set -- $(preview_bounds)
  left=$1
  top=$2
  right=$3
  bottom=$4
  width=$((right - left))
  height=$((bottom - top))
  x1=$((left + width / 4))
  x2=$((left + width * 3 / 4))
  y1=$((top + height / 4))
  y2=$((top + height * 3 / 4))
  screenshot="$RUN_DIR/preview.png"
  "$ADB" -s "$SERIAL" exec-out screencap -p >"$screenshot"
  printf '%s%s%s%s\n' \
    "$(pixel_color "$screenshot" "$x1" "$y1")" \
    "$(pixel_color "$screenshot" "$x2" "$y1")" \
    "$(pixel_color "$screenshot" "$x1" "$y2")" \
    "$(pixel_color "$screenshot" "$x2" "$y2")"
}

await_signature() {
  expected=$1
  attempts=0
  while [ "$attempts" -lt 30 ]; do
    actual=$(preview_signature)
    printf '%s expected=%s actual=%s\n' "$(date '+%H:%M:%S')" "$expected" "$actual" \
      >>"$RUN_DIR/orientation.log"
    if [ "$actual" = "$expected" ]; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.2
  done
  echo "Preview orientation mismatch: expected $expected, got $actual" >&2
  return 1
}

sample_video_timing() {
  set -- $(preview_bounds)
  x=$((($1 + $3) / 2))
  y=$((($2 + $4) / 2))
  samples="$RUN_DIR/video-timing.log"
  screenshot="$RUN_DIR/video-sample.png"
  : >"$samples"
  count=0
  while [ "$count" -lt 36 ]; do
    timestamp=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
    "$ADB" -s "$SERIAL" exec-out screencap -p >"$screenshot"
    color=$(pixel_color "$screenshot" "$x" "$y")
    printf '%s %s\n' "$timestamp" "$color" >>"$samples"
    count=$((count + 1))
    sleep 0.08
  done
  awk '
    $2 ~ /^[RGB]$/ {
      seen[$2] = 1
      if ($2 != previous) {
        transitions += 1
        if (lastTransition > 0) {
          interval = $1 - lastTransition
          if (interval >= 0.55 && interval <= 1.50) goodIntervals += 1
        }
        if ($2 == "R" && lastRed > 0) {
          loop = $1 - lastRed
          if (loop >= 2.40 && loop <= 3.80) goodLoops += 1
        }
        if ($2 == "R") lastRed = $1
        lastTransition = $1
        previous = $2
      }
    }
    END {
      if (!seen["R"] || !seen["G"] || !seen["B"] ||
          transitions < 6 || goodIntervals < 4 || goodLoops < 1) exit 1
    }
  ' "$samples"
}

.build/debug/camrelay run --platform android --avd "$AVD" --session "$SESSION" \
  --no-interactive \
  --fixture pattern=.build/fixtures/checkerboard.png \
  --fixture colors=.build/fixtures/colors.mp4 \
  --fixture orientation-image=.build/fixtures/orientation.png \
  --fixture orientation-video=.build/fixtures/orientation-rotate90.mp4 \
  --initial pattern >"$RUN_DIR/relay.log" 2>&1 &
RELAY_PID=$!

status=$(control wait --timeout 150s --json)
printf '%s\n' "$status" >"$RUN_DIR/ready.json"
SERIAL=$(printf '%s\n' "$status" | jq -er \
  'select(.error == null and .status.selected == "pattern") | .status.simulatorID')
rg -q 'is ready in Android AVD' "$RUN_DIR/relay.log"

"$ADB" -s "$SERIAL" install -r "$APK" >"$RUN_DIR/install.log"
"$ADB" -s "$SERIAL" shell pm grant "$APP_ID" android.permission.CAMERA
"$ADB" -s "$SERIAL" shell am force-stop "$APP_ID"
"$ADB" -s "$SERIAL" shell am start -W -n "$APP_ID/.MainActivity" >/dev/null
await_camera
await_ui 'Use back camera'
APP_PID=$("$ADB" -s "$SERIAL" shell pidof "$APP_ID")
test -n "$APP_PID"

control select pattern --json | jq -e '.error == null and .status.selected == "pattern"' >/dev/null
open_action switch-camera
await_ui 'Use front camera'
await_ui 'Camera: active'
open_action capture
await_ui 'PHOTO CAPTURED'
await_ui 'Back camera'
open_action close-photo
await_ui 'Camera: active'

control select orientation-image --json | jq -e '.error == null and .status.selected == "orientation-image"' >/dev/null
await_signature RGBY

control select orientation-video --json | jq -e '.error == null and .status.selected == "orientation-video"' >/dev/null
await_signature BRYG

control select colors --json | jq -e '.error == null and .status.selected == "colors"' >/dev/null
control replay --json | jq -e '.error == null and .status.selected == "colors"' >/dev/null
sample_video_timing

before=$(control status --json | jq -r '.status.generation')
if control select missing --json >"$RUN_DIR/failed-selection.json"; then
  echo "Unknown fixture unexpectedly succeeded." >&2
  exit 1
fi
control status --json | jq -e --argjson generation "$before" \
  '.status.selected == "colors" and .status.generation == $generation' >/dev/null

test "$("$ADB" -s "$SERIAL" shell pidof "$APP_ID")" = "$APP_PID"
if rg -q 'Camera interrupted|Photo not captured' "$RUN_DIR/window.xml"; then
  echo "The Expo camera reported an error." >&2
  exit 1
fi

control stop >/dev/null
wait "$RELAY_PID"
RELAY_PID=

attempts=0
while "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  [ "$attempts" -lt 60 ] || { echo "Emulator did not stop." >&2; exit 1; }
  sleep 0.25
done

if [ "$ORIGINAL_ENVIRONMENT" = missing ]; then
  test ! -e "$ENVIRONMENT_FILE"
else
  test "$(shasum -a 256 "$ENVIRONMENT_FILE" | awk '{print $1}')" = "$ORIGINAL_ENVIRONMENT"
  test "$(stat -f '%Lp' "$ENVIRONMENT_FILE")" = "$ORIGINAL_PERMISSIONS"
fi

echo "PASS: Android image/video preview, source timing, orientation, front/back preview, photo capture, switching, and cleanup"
