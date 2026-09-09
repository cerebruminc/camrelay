#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT_DIR="$PROJECT_DIR/.build/fixtures"
GENERATOR="$PROJECT_DIR/.build/tools/FixtureGenerator"

mkdir -p "$(dirname "$GENERATOR")"
xcrun clang \
  -fobjc-arc \
  -framework Foundation \
  -framework AVFoundation \
  -framework CoreGraphics \
  -framework CoreImage \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework ImageIO \
  "$PROJECT_DIR/Tests/Fixtures/FixtureGenerator.m" \
  -o "$GENERATOR"

"$GENERATOR" "$OUTPUT_DIR"
