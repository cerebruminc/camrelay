# CamRelay

CamRelay uses an image or video fixture as the camera feed for apps running in an iOS Simulator or Android Emulator.

The app under test does not need CamRelay code, imports, SDK integration, or special build settings. It continues to use the platform's standard camera APIs.

## Quick start

Build the CLI from the repository root:

```sh
swift build
```

For iOS, also build the Simulator runtime, boot exactly one Simulator, and start a relay:

```sh
./scripts/build-runtime.sh
.build/debug/camrelay path/to/fixture.mp4
```

Launch or relaunch the app after the relay is ready. Stop the relay with Ctrl-C.

For Android, list the available Android Virtual Devices and choose one of the printed names:

```sh
CAMRELAY_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
"$CAMRELAY_SDK/emulator/emulator" -list-avds

AVD_NAME=your_avd_name
.build/debug/camrelay emulator start --platform android --avd "$AVD_NAME"
.build/debug/camrelay --platform android --avd "$AVD_NAME" path/to/fixture.mp4
# After stopping the relay:
.build/debug/camrelay emulator stop --platform android --avd "$AVD_NAME"
```

Stopping an Android relay leaves the emulator and app running. Use `emulator stop` when you are finished with the AVD.

## Capabilities

- Image and video fixtures with deterministic looping.
- Front and back cameras exposed through standard platform camera APIs.
- Live switching between named fixtures without restarting the app.
- Replay and session control from terminal keys or separate CLI processes.
- Simulator-wide delivery to multiple iOS app processes.
- Preview and photo capture on both platforms, with additional AVFoundation capture features on iOS.
- Commands to start and stop a compatible Android Emulator.

## Documentation

- [Usage](docs/usage.md): build and run CamRelay, switch fixtures, and use it from CI.
- [CLI reference](docs/cli.md): commands, options, status output, and exit codes.
- [iOS Simulator](docs/ios.md): activation, camera compatibility, and platform limitations.
- [Android Emulator](docs/android.md): AVD setup, start and stop behavior, compatibility, and limitations.
- [Architecture](docs/architecture.md): how CamRelay delivers fixtures to apps on each platform.
- [Development](docs/development.md): repository layout, build details, and tests.
