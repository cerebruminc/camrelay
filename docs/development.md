# Development

This guide covers the repository structure, builds, and tests. See [Usage](usage.md) for instructions on running CamRelay.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/CamRelayCore` | Portable models, parsing, validation, leases, and playback-clock state |
| `Sources/CamRelayCLI` | CLI commands, terminal controls, signals, and output |
| `Sources/CamRelayIOS` | iOS Simulator activation, decoding, playback, control socket, and frame server |
| `Sources/CamRelayAndroid` | Android SDK and AVD discovery, emulator start and stop commands, media preparation, and Emulator control |
| `Runtime/CamRelayRuntime` | Objective-C runtime injected into iOS Simulator apps |
| `Examples/CamRelayProbe` | Native AVFoundation validation app |
| `Examples/CamRelayExpo` | Expo and VisionCamera validation app for both platforms |
| `Tests` | Swift unit tests and deterministic fixture utilities |
| `scripts` | Build and end-to-end validation scripts |

Shared code must remain buildable without importing Apple-only frameworks. Add a platform module when it has working behavior; do not add empty targets for planned backends.

## Build

Build the iOS runtime and debug CLI:

```sh
./scripts/build-runtime.sh
swift build
.build/debug/camrelay --help
```

Build an optimized CLI with `swift build -c release`.

`scripts/build-runtime.sh` compiles the Objective-C runtime for arm64 and x86_64 iOS Simulator, combines the slices into `.build/runtime/CamRelayRuntime.dylib`, verifies both architectures, and applies an ad hoc signature.

The Swift package targets macOS 14 or newer with Swift 6.2. Platform-specific Apple frameworks remain outside `CamRelayCore`.

## Unit tests

Run the smallest filtered test that covers a change first:

```sh
swift test --filter parsesNamedFixtures
```

Run the complete Swift test suite when shared behavior or interfaces may be affected:

```sh
swift test
```

The suite covers command and fixture validation, source-clock behavior, Simulator selection and activation commands, output scheduling and conversion, local sockets and leases, CRF3 transport, switching, acknowledgements, reconnection, slow-client isolation, Android SDK and AVD discovery, emulator startup and shutdown, and media control.

## Deterministic fixtures

Generate local image and video fixtures:

```sh
./scripts/generate-fixtures.sh
```

Outputs are written to `.build/fixtures`. They include solid colors, a changing-color video, a checkerboard, moving shapes, and image/video orientation patterns. Generated media is disposable and must not be committed.

## Native iOS probe

`CamRelayProbe` uses standard AVFoundation APIs and does not import or link CamRelay.

Build it with:

```sh
./scripts/build-probe.sh
```

The script produces:

- `.build/probe/CamRelayProbe.app` with arm64 and x86_64 slices
- `.build/probe-x86_64/CamRelayProbe.app` with an x86_64-only executable

For a manual no-relay baseline:

```sh
xcrun simctl install booted .build/probe/CamRelayProbe.app
xcrun simctl launch booted org.camrelay.probe
```

The probe should report that no camera is available. With an active image or video relay, it exercises discovery, input and session configuration, video frames, preview, photo capture, movie recording, QR metadata configuration, controls, and front/back switching.

Compile the capture inspector before running pixel-comparison checks:

```sh
xcrun swiftc -parse-as-library Tests/Fixtures/CaptureInspector.swift -o .build/capture-inspector
.build/capture-inspector --fixtures .build/fixtures
```

## iOS Simulator tests

Build the runtime, CLI, probe, fixtures, and capture inspector first. Boot exactly one Simulator and stop any other relay.

Run the scenarios affected by your change:

```sh
sh scripts/validate-multifixture.sh arm64 TERM
sh scripts/validate-multifixture.sh x86_64 INT
./scripts/validate-slow-video-callback.sh
python3 scripts/validate-terminal.py
```

- `validate-multifixture.sh` checks fixture switching, stable format, capture, controls, looping, timestamps, camera reconfiguration, failed-selection preservation, delivery acknowledgement, and signal cleanup. It requires `simctl`, `jq`, and `rg`.
- `validate-slow-video-callback.sh` checks that delayed app callbacks remain memory-bounded and do not block the relay. It requires `simctl` and `jq`.
- `validate-terminal.py` uses Python's standard library to check hotkeys and terminal restoration after `q`, SIGINT, and SIGTERM.

Validation logs remain under `.build/validation`.

## Expo VisionCamera example

The [CamRelay Expo example](../Examples/CamRelayExpo/README.md) validates front/back discovery, live preview, frame-processor delivery, camera switching, and photo capture through `react-native-vision-camera`.

Install dependencies and run its local checks:

```sh
npm --prefix Examples/CamRelayExpo install
npm --prefix Examples/CamRelayExpo run typecheck
npm --prefix Examples/CamRelayExpo test
```

The example requires a native development build; it does not run in Expo Go.

For Android Emulator tests:

```sh
./scripts/generate-fixtures.sh
swift build
npm --prefix Examples/CamRelayExpo run android:validation-build
AVD_NAME=your_avd_name
./scripts/validate-android.sh "$AVD_NAME"
```

The script requires `adb`, `jq`, ImageMagick's `magick`, `rg`, and `xmllint`. It checks front/back preview, photo capture, image and video orientation, source cadence and looping, live fixture switching, failed-selection preservation, app and AVD continuity after relay shutdown, unchanged AVD configuration, and explicit AVD cleanup.

## What to test

Start with the smallest check that directly covers the change:

- Documentation-only changes need content review plus link and formatting checks.
- Isolated core or CLI changes start with the relevant filtered Swift test.
- A change to one camera feature or media type starts with its probe scenario.
- Expo-only changes start with `npm run typecheck` and the JavaScript tests.
- Runtime, transport, timing, concurrency, activation, or cleanup changes require the affected end-to-end scenarios.
- Build-script or architecture changes require checks for the affected artifacts and slices.

Expand validation when shared behavior may be affected, a focused test exposes another risk, or a full regression run is requested.

## Full validation

Run all of these checks for release candidates and changes that affect several camera features, media types, architectures, or startup and shutdown behavior:

- arm64 and x86_64 iOS Simulator app processes
- Multiple app bundles connected concurrently
- Slow or suspended clients isolated from active clients
- Static images and changing videos
- Video data, preview, photo, movie, metadata, formats, ports, and connections
- Playback looping, fixture switching, stable format, and continuous timestamps
- Session control, timeouts, failure preservation, and terminal controls
- Ctrl-C and SIGTERM cleanup
- Universal artifact architecture and code-signature checks
- Android front/back preview, capture, orientation, cadence, switching, relay cleanup, and AVD cleanup
- The full unit-test suite on each supported host architecture available for testing

List any check you could not run as unverified. Do not call a partial run full validation.

## Generated artifacts

Runtime, probe, fixture, validation, and package outputs live under `.build`. Expo's generated `ios` and `android` directories are also disposable and ignored. These files are not source and must not be committed.
