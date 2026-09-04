#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT_DIR="$PROJECT_DIR/.build/runtime"
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
OUTPUT_PATH="$OUTPUT_DIR/CamRelayRuntime.dylib"
SLICE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/camrelay-runtime.XXXXXX")

trap 'rm -rf "$SLICE_DIR"' EXIT HUP INT TERM

mkdir -p "$OUTPUT_DIR"

build_slice() {
  ARCHITECTURE=$1
  xcrun clang \
    -fobjc-arc \
    -target "$ARCHITECTURE-apple-ios18.0-simulator" \
    -isysroot "$SDK_PATH" \
    -dynamiclib \
    -install_name "$OUTPUT_PATH" \
    -framework Foundation \
    -framework AVFoundation \
    -framework CoreGraphics \
    -framework CoreImage \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework QuartzCore \
    "$PROJECT_DIR/Runtime/CamRelayRuntime/CamRelayRuntime.m" \
    -o "$SLICE_DIR/CamRelayRuntime-$ARCHITECTURE.dylib"
}

build_slice arm64
build_slice x86_64

xcrun lipo -create \
  "$SLICE_DIR/CamRelayRuntime-arm64.dylib" \
  "$SLICE_DIR/CamRelayRuntime-x86_64.dylib" \
  -output "$OUTPUT_PATH"
xcrun lipo "$OUTPUT_PATH" -verify_arch arm64 x86_64

codesign --force --sign - "$OUTPUT_PATH"
echo "$OUTPUT_PATH"
