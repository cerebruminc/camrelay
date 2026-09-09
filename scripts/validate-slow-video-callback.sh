#!/bin/sh
# Verifies that a slow AVCaptureVideoDataOutput callback cannot queue unbounded frames.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"
command -v jq >/dev/null
test -x .build/debug/camrelay
test -f .build/runtime/CamRelayRuntime.dylib
test -f .build/probe/CamRelayProbe.app/CamRelayProbe
test -f .build/fixtures/checkerboard.png
test -f .build/fixtures/moving-shapes.mp4

DEVICE=$(xcrun simctl list devices booted -j | jq -er \
  '[.devices[][] | select(.state == "Booted" and .isAvailable)] | if length == 1 then .[0].udid else error("Boot exactly one Simulator") end')
mkdir -p .build/validation
RUN_DIR=$(mktemp -d "$PROJECT_DIR/.build/validation/slow-video-callback.XXXXXX")
SESSION="slow-video-callback-$$"
RELAY_PID=
PROBE_PID=

cleanup() {
  xcrun simctl terminate "$DEVICE" org.camrelay.probe >/dev/null 2>&1 || true
  if [ -n "$RELAY_PID" ]; then
    kill -TERM "$RELAY_PID" 2>/dev/null || true
    wait "$RELAY_PID" 2>/dev/null || true
  fi
  echo "Validation artifacts: $RUN_DIR"
}
trap cleanup EXIT HUP INT TERM

control() { .build/debug/camrelay "$@" --session "$SESSION"; }

measure_memory() {
  label=$1
  shift
  xcrun simctl terminate "$DEVICE" org.camrelay.probe >/dev/null 2>&1 || true
  attempts=0
  until control status --json | jq -e '.status.connectedReceivers == 0' >/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then
      echo "Previous probe receiver did not disconnect" >&2
      exit 1
    fi
    sleep 0.1
  done

  PROBE_PID=$(xcrun simctl launch "$DEVICE" org.camrelay.probe --slow-video-callback "$@" | awk '{print $NF}')
  attempts=0
  until control status --json | jq -e '.status.connectedReceivers == 1' >/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then
      echo "Probe did not connect to the relay" >&2
      exit 1
    fi
    sleep 0.1
  done

  # Allow camera and Core Image allocations to settle before measuring growth.
  sleep 5
  before_vsz=$(ps -o vsz= -p "$PROBE_PID" | tr -d ' ')
  sleep 8
  after_vsz=$(ps -o vsz= -p "$PROBE_PID" | tr -d ' ')
  growth_kib=$((after_vsz - before_vsz))
  maximum_growth_kib=$((128 * 1024))
  if [ "$growth_kib" -gt "$maximum_growth_kib" ]; then
    echo "$label grew by $growth_kib KiB; expected no more than $maximum_growth_kib KiB" >&2
    exit 1
  fi
  echo "$label remained bounded (virtual growth ${growth_kib} KiB)"
}

.build/debug/camrelay run --session "$SESSION" --paused --no-interactive \
  --fixture pattern=.build/fixtures/checkerboard.png \
  --fixture motion=.build/fixtures/moving-shapes.mp4 \
  >"$RUN_DIR/relay.log" 2>&1 &
RELAY_PID=$!
control wait --timeout 20s --json | jq -e '.error == null and .status.paused' >/dev/null

xcrun simctl terminate "$DEVICE" org.camrelay.probe >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" .build/probe/CamRelayProbe.app
measure_memory "Late-frame discarding"
measure_memory "Late-frame backpressure" --keep-late-video-frames
echo "PASS: slow video callback memory remained bounded"
