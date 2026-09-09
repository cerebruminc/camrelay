#!/bin/sh
# Command-driven integration test. Owns only the relay and the validation probe.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"
ARCHITECTURE=${1:-arm64}
STOP_SIGNAL=${2:-TERM}
case "$ARCHITECTURE" in
  arm64) APP=.build/probe/CamRelayProbe.app ;;
  x86_64) APP=.build/probe-x86_64/CamRelayProbe.app ;;
  *) echo "Usage: $0 [arm64|x86_64] [TERM|INT]" >&2; exit 2 ;;
esac
case "$STOP_SIGNAL" in TERM|INT) ;; *) exit 2 ;; esac
command -v jq >/dev/null
command -v rg >/dev/null
test -x .build/debug/camrelay
test -f "$APP/CamRelayProbe"
test -x .build/capture-inspector
test -f .build/fixtures/colors.mp4
test -f .build/fixtures/checkerboard.png
test -f .build/fixtures/moving-shapes.mp4
test -f .build/fixtures/qr.png
mkdir -p .build/validation
RUN_DIR=$(mktemp -d "$PROJECT_DIR/.build/validation/$ARCHITECTURE.XXXXXX")
SESSION="validation-$$"
RELAY_PID=
PROBE_PID=
DEVICE=$(xcrun simctl list devices booted -j | jq -er '[.devices[][] | select(.state == "Booted" and .isAvailable)] | if length == 1 then .[0].udid else error("Boot exactly one Simulator") end')

cleanup() {
  if [ -n "$RELAY_PID" ]; then
    kill -TERM "$RELAY_PID" 2>/dev/null || true
    wait "$RELAY_PID" 2>/dev/null || true
  fi
  echo "Validation artifacts: $RUN_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

control() { .build/debug/camrelay "$@" --session "$SESSION"; }
action() { xcrun simctl spawn "$DEVICE" notifyutil -p "org.camrelay.probe.validation.$1" >/dev/null 2>&1; }
await_log() {
  pattern=$1
  attempts=0
  until rg -q "$pattern" "$RUN_DIR/probe.log"; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 200 ]; then
      echo "Missing probe assertion: $pattern" >&2
      tail -20 "$RUN_DIR/probe.log" >&2
      exit 1
    fi
    sleep 0.1
  done
}

.build/debug/camrelay run --session "$SESSION" --paused --no-interactive \
  --fixture colors=.build/fixtures/colors.mp4 \
  --fixture pattern=.build/fixtures/checkerboard.png \
  --fixture motion=.build/fixtures/moving-shapes.mp4 \
  --fixture qr=.build/fixtures/qr.png \
  --fixture still=.build/fixtures/red.png >"$RUN_DIR/relay.log" 2>&1 &
RELAY_PID=$!
control wait --timeout 20s --json | jq -e '.error == null and .status.paused' >/dev/null
rg -q 'is ready throughout' "$RUN_DIR/relay.log"
xcrun simctl terminate "$DEVICE" org.camrelay.probe >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP"
PROBE_PID=$(xcrun simctl launch --stdout="$RUN_DIR/probe.log" --stderr="$RUN_DIR/probe.log" \
  "$DEVICE" org.camrelay.probe --validation-controls | awk '{print $NF}')
await_log "using $ARCHITECTURE"
await_log 'configured=yes'
await_log 'photo=1 .*metadata=YES'

photo=1
for fixture in colors pattern motion; do
  case "$fixture" in
    colors) position=front; reference=.build/fixtures/colors.mp4 ;;
    pattern) position=back; reference=.build/fixtures/checkerboard.png ;;
    motion) position=front; reference=.build/fixtures/moving-shapes.mp4 ;;
  esac
  action "$position"
  control select "$fixture" --paused --wait-for-frame --timeout 10s --json | \
    jq -e --arg fixture "$fixture" '.error == null and .status.selected == $fixture and .status.paused and .status.width == 1280 and .status.height == 720 and .status.framesPerSecond == 24' >/dev/null
  photo=$((photo + 1))
  action capture
  await_log "photo=$photo .*camera=$position .*metadata=YES"
  captured=$(sed -n "s/.*photo=$photo .* file=//p" "$RUN_DIR/probe.log" | tail -1)
  .build/capture-inspector --compare "$reference" "$captured"
done
await_log 'reconfiguration connections=5 ports=valid'
test "$(rg -c 'reconfiguration connections=5 ports=valid' "$RUN_DIR/probe.log")" -ge 2
control select qr --paused --wait-for-frame --timeout 10s --json | \
  jq -e '.error == null and .status.selected == "qr"' >/dev/null
await_log 'metadata type=.*QR.* value=camrelay-validation corners=4 representation=valid'
control select motion --paused --wait-for-frame --timeout 10s --json >/dev/null

before=$(control status --json | jq -r '.status.generation')
if control select missing --json >"$RUN_DIR/failed-selection.json"; then exit 1; fi
control status --json | jq -e --argjson generation "$before" '.status.selected == "motion" and .status.generation == $generation' >/dev/null
control next --paused --wait-for-frame --json | jq -e '.status.selected == "qr"' >/dev/null
control next --paused --wait-for-frame --json | jq -e '.status.selected == "still"' >/dev/null
control next --paused --wait-for-frame --json | jq -e '.status.selected == "colors"' >/dev/null
control previous --paused --wait-for-frame --json | jq -e '.status.selected == "still"' >/dev/null
control select colors --paused --wait-for-frame --json >/dev/null
control replay --paused --wait-for-frame --json | jq -e '.status.positionSeconds == 0' >/dev/null
control play --wait-for-frame --json >/dev/null
sleep 4
control pause --wait-for-frame --json >"$RUN_DIR/paused.json"
sleep 0.2
control status --json | jq -e --slurpfile paused "$RUN_DIR/paused.json" '.status.paused and .status.positionSeconds == $paused[0].status.positionSeconds' >/dev/null
await_log 'colors=3 transitions=[3-9][0-9]*'
await_log 'recording finished bytes=[1-9][0-9]* error=\(null\)'
if rg -q 'photo .*failed|ports=invalid|configured=no' "$RUN_DIR/probe.log"; then exit 1; fi
awk '/frame=.*pts=/ {
  for(i=1;i<=NF;i++) if($i ~ /^pts=/) { t=substr($i,5)+0; if(seen && t<=previous) exit 1; previous=t; seen=1 }
} END { if(!seen) exit 1 }' "$RUN_DIR/probe.log"

kill -"$STOP_SIGNAL" "$RELAY_PID"
wait "$RELAY_PID"
RELAY_PID=
for key in DYLD_INSERT_LIBRARIES CAMRELAY_PORT CAMRELAY_WIDTH CAMRELAY_HEIGHT CAMRELAY_FPS; do
  test -z "$(xcrun simctl spawn "$DEVICE" launchctl getenv "$key")"
done
kill -0 "$PROBE_PID"
echo "PASS: $ARCHITECTURE multi-fixture capture, controls, looping, timestamps, and SIG$STOP_SIGNAL cleanup"
