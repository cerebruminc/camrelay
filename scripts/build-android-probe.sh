#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_SDK="$HOME/Library/Android/sdk"
if [ "$(uname -s)" = Linux ]; then DEFAULT_SDK="$HOME/Android/Sdk"; fi
SDK_ROOT=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$DEFAULT_SDK}}
ANDROID_JAR="$SDK_ROOT/platforms/android-35/android.jar"
TOOLS="$SDK_ROOT/build-tools/36.0.0"
SOURCE_DIR="$PROJECT_DIR/Examples/CamRelayAndroidProbe"
OUTPUT_DIR="$PROJECT_DIR/.build/android-probe"
APK="$OUTPUT_DIR/CamRelayAndroidProbe.apk"

if [ -n "${JAVA_HOME:-}" ]; then PATH="$JAVA_HOME/bin:$PATH"; export PATH; fi
for tool in javac jar keytool zip; do command -v "$tool" >/dev/null; done
test -f "$ANDROID_JAR"
for tool in aapt2 d8 zipalign apksigner; do test -x "$TOOLS/$tool"; done

mkdir -p "$OUTPUT_DIR"
BUILD_DIR=$(mktemp -d "$OUTPUT_DIR/compile.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM
mkdir -p "$BUILD_DIR/classes" "$BUILD_DIR/dex"

javac --release 8 -classpath "$ANDROID_JAR" -d "$BUILD_DIR/classes" "$SOURCE_DIR/MainActivity.java"
jar cf "$BUILD_DIR/classes.jar" -C "$BUILD_DIR/classes" .
"$TOOLS/d8" --lib "$ANDROID_JAR" --min-api 26 --output "$BUILD_DIR/dex" "$BUILD_DIR/classes.jar"
"$TOOLS/aapt2" link -I "$ANDROID_JAR" --manifest "$SOURCE_DIR/AndroidManifest.xml" \
  --min-sdk-version 26 --target-sdk-version 35 -o "$BUILD_DIR/unsigned.apk"
zip -q -j "$BUILD_DIR/unsigned.apk" "$BUILD_DIR/dex/classes.dex"
"$TOOLS/zipalign" -f 4 "$BUILD_DIR/unsigned.apk" "$BUILD_DIR/aligned.apk"

# Local debug signing only; this generated key stays under the ignored .build directory.
KEYSTORE="$OUTPUT_DIR/debug.keystore"
if [ ! -f "$KEYSTORE" ]; then
  keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android \
    -alias androiddebugkey -dname 'CN=CamRelay Android Probe' -keyalg RSA -validity 3650
  chmod 600 "$KEYSTORE"
fi
"$TOOLS/apksigner" sign --ks "$KEYSTORE" --ks-key-alias androiddebugkey \
  --ks-pass pass:android --key-pass pass:android --out "$APK" "$BUILD_DIR/aligned.apk"
"$TOOLS/apksigner" verify "$APK"
echo "$APK"
