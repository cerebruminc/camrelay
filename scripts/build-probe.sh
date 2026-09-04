#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$PROJECT_DIR/.build/probe/CamRelayProbe.app"
X86_APP_DIR="$PROJECT_DIR/.build/probe-x86_64/CamRelayProbe.app"
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
SLICE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/camrelay-probe.XXXXXX")

trap 'rm -rf "$SLICE_DIR"' EXIT HUP INT TERM

mkdir -p "$APP_DIR" "$X86_APP_DIR"
cp "$PROJECT_DIR/Examples/CamRelayProbe/Info.plist" "$APP_DIR/Info.plist"
cp "$PROJECT_DIR/Examples/CamRelayProbe/Info.plist" "$X86_APP_DIR/Info.plist"

build_slice() {
  ARCHITECTURE=$1
  xcrun clang \
    -fobjc-arc \
    -target "$ARCHITECTURE-apple-ios18.0-simulator" \
    -isysroot "$SDK_PATH" \
    -framework UIKit \
    -framework ImageIO \
    -framework AVFoundation \
    -framework CoreImage \
    -framework CoreGraphics \
    -framework CoreMedia \
    -framework CoreVideo \
    "$PROJECT_DIR/Examples/CamRelayProbe/CamRelayProbe.m" \
    -o "$SLICE_DIR/CamRelayProbe-$ARCHITECTURE"
}

build_slice arm64
build_slice x86_64

xcrun lipo -create \
  "$SLICE_DIR/CamRelayProbe-arm64" \
  "$SLICE_DIR/CamRelayProbe-x86_64" \
  -output "$APP_DIR/CamRelayProbe"
xcrun lipo "$APP_DIR/CamRelayProbe" -verify_arch arm64 x86_64
cp "$SLICE_DIR/CamRelayProbe-x86_64" "$X86_APP_DIR/CamRelayProbe"
xcrun lipo "$X86_APP_DIR/CamRelayProbe" -verify_arch x86_64

codesign --force --sign - "$APP_DIR"
codesign --force --sign - "$X86_APP_DIR"
echo "$APP_DIR"
echo "$X86_APP_DIR"
