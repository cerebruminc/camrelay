#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: sh scripts/package-release.sh <release-tag> [arm64|x86_64]" >&2
  exit 2
fi

PROJECT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TAG=$1
ARCHITECTURE=${2:-$(uname -m)}
VERSION=$(cat "$PROJECT_DIR/VERSION")
if ! printf '%s\n' "$TAG" | LC_ALL=C grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' || [ "$TAG" != "v$VERSION" ]; then
  echo "Release tag must match VERSION (v$VERSION)." >&2
  exit 1
fi

case "$(uname -s)/$ARCHITECTURE" in
  Darwin/arm64|Darwin/x86_64) PLATFORM=macos ;;
  Linux/x86_64) PLATFORM=linux ;;
  *) echo "Unsupported release platform: $(uname -s)/$ARCHITECTURE" >&2; exit 1 ;;
esac

OUTPUT_DIR="$PROJECT_DIR/.build/release-assets"
SCRATCH_DIR="$PROJECT_DIR/.build/package-$PLATFORM-$ARCHITECTURE"
ARCHIVE="camrelay-$TAG-$PLATFORM-$ARCHITECTURE.tar.gz"
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/camrelay-package.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT HUP INT TERM
mkdir -p "$OUTPUT_DIR" "$STAGING_DIR/bin"
cd "$PROJECT_DIR"

if [ "$PLATFORM" = macos ]; then
  swift build -c release --product camrelay --arch "$ARCHITECTURE" --scratch-path "$SCRATCH_DIR"
  BIN_DIR=$(swift build -c release --arch "$ARCHITECTURE" --scratch-path "$SCRATCH_DIR" --show-bin-path)
  sh scripts/build-runtime.sh
  mkdir -p "$STAGING_DIR/runtime"
  cp .build/runtime/CamRelayRuntime.dylib "$STAGING_DIR/runtime/"
  xcrun install_name_tool -id '@rpath/CamRelayRuntime.dylib' "$STAGING_DIR/runtime/CamRelayRuntime.dylib"
  codesign --force --sign - "$STAGING_DIR/runtime/CamRelayRuntime.dylib"
else
  if [ "$(uname -m)" != x86_64 ]; then
    echo "Linux release builds require an x86_64 host." >&2
    exit 1
  fi
  swift build -c release --product camrelay --static-swift-stdlib --scratch-path "$SCRATCH_DIR"
  BIN_DIR=$(swift build -c release --static-swift-stdlib --scratch-path "$SCRATCH_DIR" --show-bin-path)
fi

cp "$BIN_DIR/camrelay" "$STAGING_DIR/bin/"
cp VERSION "$STAGING_DIR/"
if [ "$PLATFORM" = macos ]; then
  codesign --force --sign - "$STAGING_DIR/bin/camrelay"
  tar -czf "$OUTPUT_DIR/$ARCHIVE" -C "$STAGING_DIR" bin runtime VERSION
else
  tar -czf "$OUTPUT_DIR/$ARCHIVE" -C "$STAGING_DIR" bin VERSION
fi

sh scripts/verify-release-package.sh "$OUTPUT_DIR/$ARCHIVE" "$TAG" "$ARCHITECTURE"
(
  cd "$OUTPUT_DIR"
  if [ "$PLATFORM" = macos ]; then
    shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
  else
    sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"
  fi
)
echo "Release archive: $OUTPUT_DIR/$ARCHIVE"
