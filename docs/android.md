# Android Emulator

On Android, CamRelay controls the front and back environment cameras of an Android Virtual Device. Apps continue to use standard Android camera APIs and do not integrate with CamRelay.

## Requirements

- A macOS or Linux source build of CamRelay
- An Android SDK containing `emulator/emulator` and `platform-tools/adb`
- At least one Android Virtual Device
- On Linux, FFmpeg (`ffmpeg`, `ffprobe`, and the `libx264` encoder) and an HTTP/2-enabled `/usr/bin/curl`

On Ubuntu 24.04, install the media and control tools with:

```sh
sudo apt-get update
sudo apt-get install -y ffmpeg curl
```

CamRelay searches for the SDK in this order:

1. `ANDROID_SDK_ROOT`
2. `ANDROID_HOME`
3. `$HOME/Library/Android/sdk` on macOS or `$HOME/Android/Sdk` on Linux

It uses `ANDROID_AVD_HOME`, then `ANDROID_USER_HOME/avd`, then `$HOME/.android/avd` to find AVD data.

macOS Android validation currently uses Android Emulator 36.6.11.

On Linux, Emulator discovery checks writable directories in this order: `XDG_RUNTIME_DIR`, `/run/user/<uid>`, `ANDROID_EMULATOR_HOME`, `ANDROID_PREFS_ROOT`, `ANDROID_SDK_HOME`, and `$HOME/.android`. Private discovery files live under `avd/running` in the selected directory. CamRelay requires those files and that directory to be private and owned by the current user.

For a headless session, set `XDG_RUNTIME_DIR` to a writable directory owned by the current user before starting the Emulator and relay. Emulator display and hardware acceleration must also be configured for the Linux host.

## Select an AVD

List available AVDs:

```sh
CAMRELAY_DEFAULT_SDK="$HOME/Library/Android/sdk"
if [ "$(uname -s)" = Linux ]; then
  CAMRELAY_DEFAULT_SDK="$HOME/Android/Sdk"
fi
CAMRELAY_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$CAMRELAY_DEFAULT_SDK}}"
"$CAMRELAY_SDK/emulator/emulator" -list-avds
```

If exactly one AVD exists, `--avd` can be omitted. Otherwise, provide its name explicitly.

## Start the emulator

The selected AVD must be stopped:

```sh
swift build
AVD_NAME=your_avd_name
.build/debug/camrelay emulator start --platform android --avd "$AVD_NAME"
```

CamRelay launches the AVD with front and back environment cameras, an ephemeral localhost gRPC port, bearer-token authentication, snapshots disabled, and the boot animation disabled. It waits for Android to finish booting and for both camera mappings to become available before returning. Android boot has no internal time limit; in CI, use the workflow timeout to bound execution. If the Emulator exits during boot, CamRelay reports the failure.

An AVD that was started normally is not suitable for a relay run. Stop it and restart it with `camrelay emulator start`.

## Run a relay

Attach to the running AVD:

```sh
.build/debug/camrelay --platform android --avd "$AVD_NAME" path/to/fixture.mp4
```

The relay reads the Emulator's private discovery information and authenticates to its localhost control endpoint. It does not restart the emulator or app.

Both environment cameras show the selected fixture. CamRelay prepares temporary media so the complete image or video fits the Emulator viewport without cropping. Video orientation metadata and source cadence are preserved, and the Emulator loops the prepared result.

macOS uses Apple media frameworks; Linux uses FFmpeg. Available image and video codecs depend on the host decoder. Unsupported or undecodable media fails with a fixture-specific error.

For the included Android validation scenarios, generate fixtures on either host with `python3 scripts/generate-android-fixtures.py`. See [the native Android probe](development.md#native-android-probe) for the basic Camera2 frame check used in CI, or [the Expo example](development.md#expo-visioncamera-example) for broader preview, capture, and orientation checks.

## Switch fixtures

```sh
.build/debug/camrelay run --platform android --avd "$AVD_NAME" --session demo \
  --fixture pattern=.build/fixtures/checkerboard.png \
  --fixture colors=.build/fixtures/colors.mp4 \
  --initial pattern

.build/debug/camrelay select colors --session demo
.build/debug/camrelay replay --session demo
.build/debug/camrelay next --session demo
.build/debug/camrelay status --session demo --json
```

`select`, `replay`, `next`, and `previous` update both cameras without restarting the AVD or app. CamRelay commits the new selection and generation only after the Emulator accepts the request. A failed change leaves the previous selection active.

The Emulator ignores an identical environment-scene value, so CamRelay alternates equivalent temporary paths when replaying or reselecting a fixture. This forces the Emulator to reload the media.

## Supported controls and status

Android supports:

- `select`
- `replay`
- `next` and `previous`
- `status`, `wait`, and `stop`

The environment-camera API does not expose source pause/resume or app delivery acknowledgements. Android therefore rejects `pause`, `play`, `--paused`, and `--wait-for-frame`.

JSON status includes the fixture list, selection, and generation. Pause state is always false. Source position, output dimensions, frame rate, and receiver counts are zero because the Emulator does not provide those values to CamRelay.

## Stop the relay and emulator

Stopping a relay restores the idle environment-camera scene read from the AVD's `environment.ini` and removes its temporary media:

```sh
.build/debug/camrelay stop --session demo
```

Ctrl-C, SIGTERM, and terminal `q` perform the same cleanup. The AVD and app processes remain running, so another relay build can attach without restarting them. The Emulator persists scene changes to `environment.ini`; CamRelay restores its original contents and permissions during cleanup.

Shut down the AVD separately:

```sh
.build/debug/camrelay emulator stop --platform android --avd "$AVD_NAME"
```

The stop command waits for ADB to report the AVD's disconnection before returning.

## Compatibility and limitations

- Front and back cameras are provided through the Android Emulator's environment-camera implementation.
- Image and video preview, camera switching, and photo capture are validated with the included Expo VisionCamera example.
- The Emulator owns the camera format, frame delivery, and looping behavior.
- Pause/play, source-position reporting, and app delivery acknowledgements are unavailable.
- Relay cleanup depends on the Emulator control endpoint remaining available. If restoring the idle scene fails, CamRelay reports the error and preserves the temporary media path for diagnosis.
