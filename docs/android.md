# Android Emulator

On Android, CamRelay controls the front and back environment cameras of an Android Virtual Device. Apps continue to use standard Android camera APIs and do not integrate with CamRelay.

## Requirements

- A macOS source build of CamRelay
- An Android SDK containing `emulator/emulator` and `platform-tools/adb`
- At least one Android Virtual Device

CamRelay searches for the SDK in this order:

1. `ANDROID_SDK_ROOT`
2. `ANDROID_HOME`
3. `$HOME/Library/Android/sdk`

It uses `ANDROID_AVD_HOME`, then `ANDROID_USER_HOME/avd`, then `$HOME/.android/avd` to find AVD data.

CamRelay's Android tests currently use Android Emulator 36.6.11.

## Select an AVD

List available AVDs:

```sh
CAMRELAY_SDK="$HOME/Library/Android/sdk"
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

CamRelay launches the AVD with front and back environment cameras, an ephemeral localhost gRPC port, bearer-token authentication, snapshots disabled, and the boot animation disabled. It waits for Android to finish booting and for both camera mappings to become available before returning.

An AVD that was started normally is not suitable for a relay run. Stop it and restart it with `camrelay emulator start`.

## Run a relay

Attach to the running AVD:

```sh
.build/debug/camrelay --platform android --avd "$AVD_NAME" path/to/fixture.mp4
```

The relay reads the Emulator's private discovery information and authenticates to its localhost control endpoint. It does not restart the emulator or app.

Both environment cameras show the selected fixture. CamRelay prepares temporary media so the complete image or video fits the Emulator viewport without cropping. Video orientation metadata and source cadence are preserved, and the Emulator loops the prepared result.

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

Ctrl-C, SIGTERM, and terminal `q` perform the same cleanup. The AVD and app processes remain running, so another relay build can attach without restarting them. CamRelay reads but does not rewrite `environment.ini`.

Shut down the AVD separately:

```sh
.build/debug/camrelay emulator stop --platform android --avd "$AVD_NAME"
```

## Compatibility and limitations

- Front and back cameras are provided through the Android Emulator's environment-camera implementation.
- Image and video preview, camera switching, and photo capture are validated with the included Expo VisionCamera example.
- The Emulator owns the camera format, frame delivery, and looping behavior.
- Pause/play, source-position reporting, and app delivery acknowledgements are unavailable.
- Relay cleanup depends on the Emulator control endpoint remaining available. If restoring the idle scene fails, CamRelay reports the error and preserves the temporary media path for diagnosis.
