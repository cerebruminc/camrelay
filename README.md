# CamRelay

CamRelay supplies a media fixture as the camera feed seen by an app running in iOS Simulator or Android Emulator.

After [building from source](#build-and-run-from-source), run it from the repository root:

```sh
.build/debug/camrelay ./fixtures/colors.mp4
```

**The app under test does not need to be changed.** It continues to use standard platform camera APIs, with no CamRelay imports, SDK integration, source changes, or special build configuration.

## iOS Simulator behavior

- Accepts PNG, JPEG, HEIC, TIFF, BMP, MP4, MOV, and M4V fixtures.
- Detects one booted iOS Simulator.
- Enables the camera feed throughout the booted Simulator while CamRelay is running.
- Delivers one shared fixture timeline to multiple app processes without allowing a suspended app to block active apps.
- Presents front and back cameras through standard AVFoundation discovery and capture APIs.
- Supports video-data, photo, movie-file, preview-layer, and QR metadata capture paths.
- Switches named fixtures, replays, pauses, and resumes from terminal keys or separate CLI commands without restarting apps.
- Keeps one stable camera format for the session, using the highest-resolution supported fixture that can be decoded so a small initial image does not reduce later video quality.
- Repeats images and samples videos at the session's output rate while preserving source playback speed and loop duration.
- Removes the Simulator-wide feed and stops the relay on Ctrl-C or SIGTERM.

## Android Emulator

The Android backend accepts image and video fixtures. Start the selected Android Virtual Device once with front and back environment cameras, then attach and stop relay processes without restarting it:

```sh
CAMRELAY_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
"$CAMRELAY_SDK/emulator/emulator" -list-avds
AVD_NAME=your_avd_name
swift build
.build/debug/camrelay emulator start --platform android --avd "$AVD_NAME"
.build/debug/camrelay --platform android --avd "$AVD_NAME" .build/fixtures/checkerboard.png
# Stop the relay with Ctrl-C, q, or `camrelay stop`, then stop the AVD when finished:
.build/debug/camrelay emulator stop --platform android --avd "$AVD_NAME"
```

If only one AVD exists, omit `--avd`. CamRelay finds the SDK through `ANDROID_SDK_ROOT`, `ANDROID_HOME`, or the standard macOS SDK location. `emulator start` requires the selected AVD to be stopped. Relay runs require that AVD to have been started with this command.

The emulator exposes both cameras through standard Android camera APIs. CamRelay controls it through an ephemeral, token-protected gRPC endpoint restricted to localhost. It prepares temporary copies of fixtures so the emulator's environment-camera framing shows the complete image or video without cropping. Ctrl-C, SIGTERM, and `camrelay stop` restore the AVD's idle scene and remove temporary media, but leave the emulator and app running. Only `emulator stop` shuts down the AVD. This lets a rebuilt CamRelay attach to the same emulator without forcing an app or emulator restart.

Named fixtures can switch without restarting the emulator or app:

```sh
AVD_NAME=your_avd_name
.build/debug/camrelay run --platform android --avd "$AVD_NAME" --session demo \
  --fixture pattern=.build/fixtures/checkerboard.png \
  --fixture colors=.build/fixtures/colors.mp4 \
  --initial pattern

.build/debug/camrelay select colors --session demo
.build/debug/camrelay replay --session demo
.build/debug/camrelay next --session demo
.build/debug/camrelay status --session demo --json
```

CamRelay preserves video cadence and orientation while preparing it, and the Android Emulator loops the result. CamRelay supports `select`, `replay`, `next`, `previous`, `status`, `wait`, and `stop` for Android. Pause/play, `--paused`, and `--wait-for-frame` are not available because the emulator environment camera does not expose those controls or app delivery acknowledgements. Android status therefore reports selection and generation, while source position, output format, and receiver counts remain zero. Android Emulator 36.6.11 is the currently validated version.

The repeatable Android check uses the included Expo VisionCamera app. It verifies front/back discovery, preview, photo capture, image and video orientation, video cadence and looping, live fixture switching without an app restart, failed-selection preservation, relay shutdown without emulator or app shutdown, and explicit AVD cleanup:

```sh
./scripts/generate-fixtures.sh
swift build
cd Examples/CamRelayExpo
npm run android:validation-build
cd ../..
AVD_NAME=your_avd_name
./scripts/validate-android.sh "$AVD_NAME"
```

The script requires `adb`, `jq`, ImageMagick, `rg`, and `xmllint`. It starts and stops the AVD with the separate lifecycle commands and leaves its logs under `.build/validation`.

## Build and run from source

Requirements:

- Apple Silicon Mac
- Xcode with an iOS Simulator runtime
- Swift 6.2 or newer

From the repository root, build the Simulator runtime and CLI once:

```sh
./scripts/build-runtime.sh
swift build
```

The examples below use `.build/debug/camrelay` unless noted otherwise. Running the executable directly reuses the build; rebuild after changing the source. If `camrelay` is installed on your path, you can use it in place of `.build/debug/camrelay`.

The runtime build contains both arm64 and x86_64 Simulator slices. Each app automatically loads its matching slice when it launches, so the host CLI does not need to use the same architecture as the app.

Boot one Simulator, then run:

```sh
.build/debug/camrelay /absolute/or/relative/path/to/fixture.mp4
```

### Release build

To compile an optimized CLI, run these commands from the repository root:

```sh
./scripts/build-runtime.sh
swift build -c release
```

The release executable is `.build/release/camrelay`. With one Simulator booted, run:

```sh
.build/release/camrelay /absolute/or/relative/path/to/fixture.mp4
```

Use `.build/release/camrelay` in place of `.build/debug/camrelay` for the other commands in this README. Both builds use `.build/runtime/CamRelayRuntime.dylib`, which the runtime script builds separately. The `-c release` option applies to the Swift CLI build.

### Simulator-wide activation

CamRelay enables the camera feed for the booted Simulator. It does not inspect installed apps, select a bundle identifier, or launch a specific app.

After CamRelay starts, launch or relaunch any app in that Simulator. Every app process launched while the relay is active inherits the same camera feed, and multiple apps can connect concurrently. Apps that were already running before CamRelay started must be relaunched because their process environment was created before the Simulator-wide runtime was enabled.

Stopping CamRelay removes the Simulator-wide activation and disconnects every feed without terminating app processes. Apps launched afterward use the Simulator's normal camera behavior.

## Multiple fixtures

Generate a set of reusable fixtures, then start one named session from the repository root:

```sh
./scripts/generate-fixtures.sh
.build/debug/camrelay run --session demo \
  --fixture colors=.build/fixtures/colors.mp4 \
  --fixture pattern=.build/fixtures/checkerboard.png \
  --fixture motion=.build/fixtures/moving-shapes.mp4 \
  --initial colors --paused
```

Launch the app once after the session is ready. On iOS, the initial frame stays visible until you start playback. Switching fixtures changes both cameras without CamRelay knowing which app screen is visible.

- `colors.mp4`: a 320×240, 15 fps video that cycles through red, green, and blue over three seconds.
- `checkerboard.png`: a 480×640 black-and-white pattern for checking static input and aspect fitting.
- `moving-shapes.mp4`: a 1280×720, 24 fps video with a moving circle and square, looping every three seconds.
- `orientation.png`: a portrait quadrant pattern for checking image orientation.
- `orientation-rotate90.mp4`: a landscape-encoded quadrant video with rotation metadata for checking video orientation.

The fixtures are generated locally under `.build/fixtures`; no footage or downloads are needed. Fixture names are your own labels, and the app never receives them.

In an interactive terminal, press `1` through `9` to select a fixture, `n` for next, `b` for previous, `r` to replay, and `q` to stop. On iOS, space pauses or resumes. Next and previous wrap around the fixture list. Selection and replay start at the beginning and play immediately.

From another terminal, or from a test runner:

```sh
.build/debug/camrelay play --session demo --wait-for-frame
.build/debug/camrelay select pattern --session demo --wait-for-frame
.build/debug/camrelay select motion --session demo --wait-for-frame
.build/debug/camrelay replay --session demo
.build/debug/camrelay pause --session demo
.build/debug/camrelay status --session demo --json
.build/debug/camrelay stop --session demo
```

On iOS, use `--paused` on select, replay, next, or previous to hold the replacement's first frame. Pausing holds the image but keeps camera samples and their timestamps advancing. A failed file load leaves the previous source selected on either platform.

On iOS, CamRelay inspects the fixture set at startup and uses the supported, decodable fixture with the largest pixel count as the stable camera format. If fixtures have the same dimensions, the higher frame rate wins. `--initial` controls which fixture appears first, not the output resolution. In this example, the 1280×720, 24 fps clip sets the format even though the 320×240 clip is selected initially. On Android, CamRelay fits each source into the emulator's environment-camera viewport; the emulator owns the camera format and playback loop.

### CI orchestration

```sh
.build/debug/camrelay run --session demo --no-interactive --paused \
  --fixture colors=.build/fixtures/colors.mp4 \
  --fixture pattern=.build/fixtures/checkerboard.png \
  --fixture motion=.build/fixtures/moving-shapes.mp4 &
relay_pid=$!
trap '.build/debug/camrelay stop --session demo >/dev/null 2>&1 || true; wait "$relay_pid"' EXIT

.build/debug/camrelay wait --session demo --timeout 30s --json
# Launch the app and navigate to its camera with your existing test runner.
.build/debug/camrelay select colors --session demo --paused --wait-for-frame --timeout 10s
# Capture a photo and assert that it is red.
.build/debug/camrelay select pattern --session demo --paused --wait-for-frame --timeout 10s
# Capture another photo and assert that the checkerboard is visible.
.build/debug/camrelay select motion --session demo --wait-for-frame --timeout 10s
# Assert that the preview changes as the shapes move.
```

`wait` waits for the named relay's control endpoint to become ready, not for an app camera to open. `--wait-for-frame` requires at least one connected capture receiver and an acknowledgement from every currently connected receiver for the new playback generation. It confirms runtime receipt, not an app's photo completion or a rendered screen. Keep your test runner's own capture and UI assertions.

A suspended receiver can cause a delivery timeout even while the foreground app continues receiving frames. A timed-out selection remains active; check `status --json` before retrying. Another playback change can supersede a pending wait. Commands exit with status 1 for operational failures and 2 for invalid arguments; `--json` returns a structured `status` and/or `error` object. The status includes the selection, pause state, generation, source position since selection (including loops), camera format, and receiver counts. A decoder failure appears in `status.error` and holds the last frame.

Session names default to `default`. Only one relay may own a Simulator at a time, even under different session names. Named sessions let shell jobs address the intended relay without app identifiers. Run `.build/debug/camrelay --help` for all options.

## Validation app

`CamRelayProbe` is a small UIKit application that uses standard AVFoundation APIs for discovery, device input, session configuration, video frames, preview, photo capture, movie recording, and metadata detection. It does not import or link CamRelay, demonstrating the same integration boundary as an app under test.

Build the validation app and deterministic fixtures:

```sh
./scripts/build-probe.sh
./scripts/generate-fixtures.sh
```

The probe build creates two app bundles:

- `.build/probe/CamRelayProbe.app` contains arm64 and x86_64 slices.
- `.build/probe-x86_64/CamRelayProbe.app` is x86_64-only and exercises the translated Simulator path.

Install and normally launch the generated app for the no-relay baseline:

```sh
xcrun simctl install booted .build/probe/CamRelayProbe.app
xcrun simctl launch booted org.camrelay.probe
```

For an x86_64-specific validation run, install the x86_64-only bundle instead:

```sh
xcrun simctl install booted .build/probe-x86_64/CamRelayProbe.app
```

Exercise both media paths:

```sh
.build/debug/camrelay .build/fixtures/red.png
.build/debug/camrelay .build/fixtures/colors.mp4
```

Relaunch the validation app after starting each relay command. The CLI does not select or launch it.

Expected results:

1. Launching the validation app normally shows `No camera found`.
2. `red.png` shows red and an increasing frame count, captures a JPEG photo, and records a short movie.
3. The preview layer remains active while frames are delivered.
4. `colors.mp4` changes between red, green, and blue, continues increasing the frame count, and loops.

Run the unit-test suite with:

```sh
swift test
```

The repeatable multi-fixture probe test uses `simctl`, `jq`, and `rg`. Build the runtime, probe, CLI, and fixtures first, boot exactly one Simulator, and stop any other relay. Compile the capture inspector once to compare saved photos against fixture pixels:

```sh
xcrun swiftc -parse-as-library Tests/Fixtures/CaptureInspector.swift -o .build/capture-inspector
.build/capture-inspector --fixtures .build/fixtures
```

The script installs the selected probe build, captures each fixture while switching cameras in both directions, checks controls and timestamps, and verifies signal cleanup. It does not relaunch the probe between fixture selections.

```sh
sh scripts/validate-multifixture.sh arm64 TERM
sh scripts/validate-multifixture.sh x86_64 INT
./scripts/validate-slow-video-callback.sh
python3 scripts/validate-terminal.py
```

Logs remain under `.build/validation`. The slow-callback test verifies that late video-data frames remain memory-bounded when an app cannot process frames in real time. The probe stays open after the relay stops. The terminal test uses Python's standard library to check hotkeys and terminal restoration after quit, SIGINT, and SIGTERM. These scripts control only the validation app; CamRelay itself does not manage apps.

## Expo VisionCamera example

`CamRelayExpo` is an Expo development build that renders a live preview with `react-native-vision-camera` on iOS Simulator and Android Emulator. Use it when compatibility needs to be checked through a React Native camera library without changing an app under test.

Install its dependencies once:

```sh
cd Examples/CamRelayExpo
npm install
```

For iOS, boot one Simulator and create the first native build:

```sh
npm run ios
```

With the runtime and CLI built as described above, start CamRelay from the repository root and relaunch **CamRelay Expo**:

```sh
.build/debug/camrelay /absolute/path/to/fixture.mp4
```

The example reports camera and preview state over the live view. Visible motion confirms that the video fixture is advancing. Its native development build is required because VisionCamera is not included in Expo Go.

For Android, create the release APK used by the repeatable validation script:

```sh
npm run android:validation-build
```

The generated `ios` and `android` directories are disposable and ignored. After the first development build, JavaScript-only changes can use `npm start` with the already installed app. See [`Examples/CamRelayExpo/README.md`](Examples/CamRelayExpo/README.md) for both workflows.

### Choosing validation scope

Start with the smallest test or check that directly covers the change. A documentation-only change normally needs documentation review and applicable formatting or link checks; it does not require rebuilding the runtime or running Simulator scenarios. For an isolated code change, run the relevant unit test or probe scenario first and expand validation only when shared behavior, additional media paths, multiple architectures, or Simulator lifecycle behavior may be affected.

The complete end-to-end validation matrix is intended for broad changes and release validation, not as the default for every small change.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the detailed design, including session control, process boundaries, CRF3 transport, the AVFoundation runtime, media outputs, lifecycle, and validation.

```text
media file
   │
   ▼
CamRelay CLI
   ├── iOS: Apple decoder ── loopback ── injected Simulator runtime
   └── Android: authenticated localhost control ── Emulator environment camera
                                                        │
                                                        ▼
                                             Standard platform camera APIs
```

- `CamRelayCore` owns portable fixture validation, command models, and playback-clock state.
- `CamRelayIOS` owns Simulator selection, Simulator-wide activation, media decoding, and the local frame server.
- `CamRelayAndroid` provides AVD selection, explicit emulator lifecycle commands, environment-camera activation, and authenticated emulator control.
- `CamRelayRuntime` is an Objective-C dynamic library built for iOS Simulator. It exposes synthetic front and back cameras and implements the common AVFoundation capture surfaces.
- `CamRelayProbe` validates the standard AVFoundation path independently.
- `CamRelayExpo` validates the same feed through Expo and `react-native-vision-camera`.

The transport boundary keeps platform-specific code outside the portable core and supports adding other virtual-device backends in the future.

## Camera API compatibility

CamRelay is intended to provide broad compatibility with the common AVFoundation camera surfaces used by iOS apps. Compatibility work should be implemented as a general platform layer and validated across representative applications, not tailored to a single app or camera SDK.

The compatibility layer currently includes:

- Front and back wide-angle camera discovery and video authorization.
- Fixture-sized formats, frame-rate ranges, device input ports, session presets, and capture connections.
- Focus, exposure, white-balance, zoom, orientation, mirroring, and stabilization properties.
- Video preferred-transform metadata is applied before frames enter the synthetic camera pipeline.
- BGRA and bi-planar YUV delivery through `AVCaptureVideoDataOutput`.
- `AVCaptureVideoPreviewLayer` rendering.
- JPEG photo capture and metadata customization through `AVCapturePhotoOutput`.
- H.264 movie recording through `AVCaptureMovieFileOutput`.
- QR-code metadata delivery through `AVCaptureMetadataOutput`.

These capabilities are exposed by default as platform behavior. They are not selected or implemented differently for individual apps.

## Current limitations

- The host CLI is currently built and tested on Apple Silicon. The injected Simulator runtime supports both arm64 and x86_64 apps.
- Running an x86_64 Simulator app on Apple Silicon requires the macOS translation component.
- The synthetic device exposes one stable format derived from the highest-resolution supported fixture that can be decoded at startup.
- Photo export supports metadata replacement; replacement thumbnails and auxiliary depth or matte images are not supported.
- Depth data, audio capture, raw photos, and non-QR metadata types are not yet synthesized.
- Focus, exposure, white-balance, stabilization, and zoom configuration are accepted for compatibility but do not alter fixture pixels.
- Raw BGRA frames use a loopback TCP stream, so high-resolution throughput depends on the host Mac and should be validated with representative fixtures.
- Android pause/play and delivery acknowledgement controls are not available.
