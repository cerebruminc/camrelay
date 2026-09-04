# CamRelay

CamRelay supplies an image or video file as the camera feed seen by an app running in iOS Simulator.

```sh
camrelay ./fixtures/blink.mp4
```

**The app under test does not need to be changed.** It continues to use standard AVFoundation camera APIs, with no CamRelay imports, SDK integration, source changes, or special build configuration.

## Current behavior

- Accepts PNG, JPEG, HEIC, TIFF, BMP, MP4, MOV, and M4V fixtures.
- Detects one booted iOS Simulator.
- Enables the camera feed throughout the booted Simulator while CamRelay is running.
- Delivers one shared fixture timeline to multiple app processes without allowing a suspended app to block active apps.
- Presents front and back cameras through standard AVFoundation discovery and capture APIs.
- Supports video-data, photo, movie-file, preview-layer, and QR metadata capture paths.
- Repeats images at 30 frames per second.
- Plays videos from their source frame timestamps and loops them at their original duration.
- Removes the Simulator-wide feed and stops the relay on Ctrl-C or SIGTERM.

## Build and run from source

Requirements:

- Apple Silicon Mac
- Xcode with an iOS Simulator runtime
- Swift 6.2 or newer

Build the Simulator runtime and CLI:

```sh
./scripts/build-runtime.sh
swift build
```

The runtime build contains both arm64 and x86_64 Simulator slices. Each app automatically loads its matching slice when it launches, so the host CLI does not need to use the same architecture as the app.

Boot one Simulator, then run:

```sh
swift run camrelay /absolute/or/relative/path/to/fixture.mp4
```

### Simulator-wide activation

CamRelay enables the camera feed for the booted Simulator. It does not inspect installed apps, select a bundle identifier, or launch a specific app.

After CamRelay starts, launch or relaunch any app in that Simulator. Every app process launched while the relay is active inherits the same camera feed, and multiple apps can connect concurrently. Apps that were already running before CamRelay started must be relaunched because their process environment was created before the Simulator-wide runtime was enabled.

Stopping CamRelay removes the Simulator-wide activation and disconnects every feed without terminating app processes. Apps launched afterward use the Simulator's normal camera behavior.

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
swift run camrelay .build/fixtures/red.png
swift run camrelay .build/fixtures/colors.mp4
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

## Expo VisionCamera example

`CamRelayExpo` is an Expo development build that renders a live preview with `react-native-vision-camera`. Use it when compatibility needs to be checked through a React Native camera library without building another application.

Install its dependencies once:

```sh
cd Examples/CamRelayExpo
npm install
```

Boot one iOS Simulator and create the first native build:

```sh
npm run ios
```

Then start CamRelay from the repository root and relaunch **CamRelay Expo**:

```sh
./scripts/build-runtime.sh
swift run camrelay /absolute/path/to/fixture.mp4
```

The example reports camera and preview state over the live view. Visible motion confirms that the video fixture is advancing. Its native development build is required because VisionCamera is not included in Expo Go.

The generated `ios` directory is disposable and ignored. After the first native build, JavaScript-only changes can use `npm start` with the already installed app. See [`Examples/CamRelayExpo/README.md`](Examples/CamRelayExpo/README.md) for the full workflow and Simulator-specific details.

### Choosing validation scope

Start with the smallest test or check that directly covers the change. A documentation-only change normally needs documentation review and applicable formatting or link checks; it does not require rebuilding the runtime or running Simulator scenarios. For an isolated code change, run the relevant unit test or probe scenario first and expand validation only when shared behavior, additional media paths, multiple architectures, or Simulator lifecycle behavior may be affected.

The complete end-to-end validation matrix is intended for broad changes and release validation, not as the default for every small change.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the detailed design, including process boundaries, CRF2 transport, the AVFoundation runtime, media outputs, lifecycle, and validation.

```text
media file
   │
   ▼
CamRelay CLI ── Apple media decoder ── loopback broadcast
                                               │
                         ┌─────────────────────┴─────────────────────┐
                         ▼                                           ▼
             Runtime in app process A                    Runtime in app process B
                         │                                           │
                         └──────── Standard camera APIs ──────────────┘
```

- `CamRelayCore` owns portable fixture validation.
- `CamRelayIOS` owns Simulator selection, Simulator-wide activation, media decoding, and the local frame server.
- `CamRelayRuntime` is a small Objective-C dynamic library built for iOS Simulator. It exposes synthetic front and back cameras and implements the common AVFoundation capture surfaces.
- `CamRelayProbe` validates the standard AVFoundation path independently.
- `CamRelayExpo` validates the same feed through Expo and `react-native-vision-camera`.

The transport boundary keeps platform-specific code outside the portable core and supports adding other virtual-device backends in the future.

## Camera API compatibility

CamRelay is intended to provide broad compatibility with the common AVFoundation camera surfaces used by iOS apps. Compatibility work should be implemented as a general platform layer and validated across representative applications, not tailored to a single app or camera SDK.

The compatibility layer currently includes:

- Front and back wide-angle camera discovery and video authorization.
- Fixture-sized formats, frame-rate ranges, device input ports, session presets, and capture connections.
- Focus, exposure, white-balance, zoom, orientation, mirroring, and stabilization properties.
- BGRA and bi-planar YUV delivery through `AVCaptureVideoDataOutput`.
- `AVCaptureVideoPreviewLayer` rendering.
- JPEG photo capture through `AVCapturePhotoOutput`.
- H.264 movie recording through `AVCaptureMovieFileOutput`.
- QR-code metadata delivery through `AVCaptureMetadataOutput`.

These capabilities are exposed by default as platform behavior. They are not selected or implemented differently for individual apps.

## Current limitations

- The host CLI is currently built and tested on Apple Silicon. The injected Simulator runtime supports both arm64 and x86_64 apps.
- Running an x86_64 Simulator app on Apple Silicon requires the macOS translation component.
- Video track rotation metadata is not applied yet, so portrait video may appear rotated when its pixels are stored sideways.
- The synthetic device currently exposes one format derived from the fixture dimensions and frame rate.
- Depth data, audio capture, raw photos, and non-QR metadata types are not yet synthesized.
- Focus, exposure, white-balance, stabilization, and zoom configuration are accepted for compatibility but do not alter fixture pixels.
- Raw BGRA frames use a loopback TCP stream, so high-resolution throughput depends on the host Mac and should be validated with representative fixtures.
- Additional virtual-device platforms are not yet supported.
