#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "Usage: sh scripts/verify-release-package.sh <archive> <release-tag> <architecture>" >&2
  exit 2
fi

ARCHIVE=$(CDPATH='' cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")
TAG=$2
ARCHITECTURE=$3
VERIFY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/camrelay-verify.XXXXXX")
trap 'rm -rf "$VERIFY_DIR"' EXIT HUP INT TERM
tar -xzf "$ARCHIVE" -C "$VERIFY_DIR"
test -x "$VERIFY_DIR/bin/camrelay"
test "$(cat "$VERIFY_DIR/VERSION")" = "${TAG#v}"

# Run the extracted executable through PATH, outside the source checkout.
ACTUAL_VERSION=$(
  cd "$VERIFY_DIR"
  PATH="$VERIFY_DIR/bin:$PATH" camrelay --version
)
test "$ACTUAL_VERSION" = "camrelay ${TAG#v}"
(
  cd "$VERIFY_DIR"
  PATH="$VERIFY_DIR/bin:$PATH" camrelay --help > /dev/null
)

case "$(uname -s)/$ARCHITECTURE" in
  Darwin/arm64|Darwin/x86_64)
    test "$(xcrun lipo -archs "$VERIFY_DIR/bin/camrelay")" = "$ARCHITECTURE"
    xcrun lipo "$VERIFY_DIR/runtime/CamRelayRuntime.dylib" -verify_arch arm64 x86_64
    codesign --verify --strict "$VERIFY_DIR/bin/camrelay"
    codesign --verify --strict "$VERIFY_DIR/runtime/CamRelayRuntime.dylib"
    test "$(xcrun otool -D "$VERIFY_DIR/runtime/CamRelayRuntime.dylib" | tail -n 1)" = '@rpath/CamRelayRuntime.dylib'
    ;;
  Linux/x86_64)
    file "$VERIFY_DIR/bin/camrelay" | grep -Eq 'ELF 64-bit.*x86-64'
    test ! -e "$VERIFY_DIR/runtime"
    DEPENDENCIES=$(ldd "$VERIFY_DIR/bin/camrelay")
    if printf '%s\n' "$DEPENDENCIES" | grep -Eq 'libswift|libFoundation|lib_Foundation|libdispatch|libBlocksRuntime|not found'; then
      echo "Linux package requires missing libraries or a shared Swift runtime:" >&2
      printf '%s\n' "$DEPENDENCIES" >&2
      exit 1
    fi
    ;;
  *) echo "Unsupported verification platform: $(uname -s)/$ARCHITECTURE" >&2; exit 1 ;;
esac
echo "PASS: packaged $ACTUAL_VERSION ($ARCHITECTURE)"
