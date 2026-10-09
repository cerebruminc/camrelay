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
| `Examples/CamRelayAndroidProbe` | Native Camera2 frame validation app |
| `Examples/CamRelayExpo` | Expo and VisionCamera validation app for both platforms |
| `Tests` | Swift unit tests and deterministic fixture utilities |
| `scripts` | Build and end-to-end validation scripts |

Shared code must remain buildable without importing Apple-only frameworks. Add a platform module when it has working behavior; do not add empty targets for planned backends.

## Build

On macOS, build the iOS runtime and debug CLI:

```sh
./scripts/build-runtime.sh
swift build
.build/debug/camrelay --help
```

Build an optimized CLI with `swift build -c release`.

`scripts/build-runtime.sh` compiles the Objective-C runtime for arm64 and x86_64 iOS Simulator, combines the slices into `.build/runtime/CamRelayRuntime.dylib`, verifies both architectures, and applies an ad hoc signature.

The Swift package requires Swift 6.2 and supports macOS 14 or newer and Linux. On Linux, `swift build` produces the Android CLI without the iOS Simulator implementation. Install FFmpeg for Linux media preparation and an HTTP/2-enabled `curl` for Emulator control; see [Android requirements](android.md#requirements). Platform-specific Apple frameworks remain outside `CamRelayCore`.

## Unit tests

Run the smallest filtered test that covers a change first:

```sh
swift test --filter parsesNamedFixtures
```

Run the complete Swift test suite when shared behavior or interfaces may be affected:

```sh
swift test
```

`unit-tests.yml` runs on every pull request and by manual dispatch. It runs the full Swift suite on Apple Silicon and Intel macOS, the portable and Android Swift tests on Ubuntu 24.04 x86_64 with Swift 6.2.1 and FFmpeg, and Expo type checking plus JavaScript tests with Node.js 22. Mac jobs select Xcode 26.2 on `macos-15` (arm64) and `macos-15-intel` (x86_64). Actions use version tags.

Linux tests exercise FFmpeg image fitting, rotated-video pixels, cadence and duration, caching, failed preparation, and temporary-media cleanup. Linux FFmpeg and SDK commands capture output in private temporary files and wait for their own child process, avoiding interrupted Foundation pipe reads. Command tests verify that a background ADB daemon does not block command completion, large diagnostics do not stall stdout, and arguments and errors are preserved. Simulator-specific Swift tests run only on macOS.

The workflow uses read-only repository permissions and `pull_request`, including fork PRs. Older runs for the same PR or ref are cancelled. Configure branch protection for the desired unit-test job checks.

The suite covers command and fixture validation, source-clock behavior, Simulator selection and activation commands, output scheduling and conversion, local sockets and leases, CRF3 transport, switching, acknowledgements, reconnection, slow-client isolation, Android SDK and AVD discovery, emulator startup and shutdown, and media control.

## Deterministic fixtures

Generate local image and video fixtures:

```sh
./scripts/generate-fixtures.sh
```

Outputs are written to `.build/fixtures`. They include solid colors, a changing-color video, a checkerboard, moving shapes, and image/video orientation patterns. Generated media is disposable and must not be committed.

For Android tests on macOS or Linux, `python3 scripts/generate-android-fixtures.py` generates only the checkerboard, color-cycle video, and image/video orientation fixtures required by the Android validator. It requires FFmpeg and Python 3 and writes to the same directory.

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

## Native Android probe

`CamRelayAndroidProbe` consumes frames through standard Camera2 and `ImageReader` APIs. It does not import or link CamRelay, or know fixture names. Build it with JDK 17 or newer and Android SDK packages `platforms;android-35` and `build-tools;36.0.0`:

```sh
sh scripts/build-android-probe.sh
```

The script uses `javac`, `d8`, and Android packaging tools to produce `.build/android-probe/CamRelayAndroidProbe.apk`. It requires no Gradle, npm, Expo, or React Native dependencies. Its local debug signing key stays under `.build` and must not be committed or uploaded.

For a basic camera delivery check on a dedicated, stopped AVD:

```sh
swift build
python3 scripts/generate-android-fixtures.py
python3 scripts/validate-android-probe.py your_avd_name
```

For a newly created AVD, initialize its `environment.ini` with `scene.mode=none` before booting it. Emulator 36.6.11 cannot reload an environment file it did not load at startup. CI creates this file for its dedicated AVD; validation preserves its contents and permissions.

The validator wakes the dedicated AVD and dismisses its keyguard before opening the probe. It checks image pixels on both cameras, video color changes and looping, camera and fixture switching, failed-selection preservation, app/AVD continuity after relay shutdown, and unchanged AVD configuration. It logs each stage and shuts down its AVD afterward. It does not check UI preview, photo capture, orientation, exact source cadence, or VisionCamera compatibility; use the Expo validator below for those scenarios.

Android integration CI uses this probe on Linux. Manual dispatch accepts `platform: android`, `ios`, or `all`. Automatic integration runs for both platforms trigger only on pushes to `release-please--branches--master`, including when release-please creates or updates its PR. Ordinary pull requests do not create integration workflow runs. Execution timeouts are configured in the workflow: the probe build has a 5-minute limit and the complete Android job has a 60-minute limit. Validation has no separate step timeout or internal execution timeouts. Logs remain under `.build/validation` and are uploaded even on failure.

On a headless Linux host, configure the private runtime directory and hardware acceleration as described below, then use `xvfb-run -a python3 scripts/validate-android-probe.py your_avd_name`.

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
python3 scripts/generate-android-fixtures.py
swift build
npm --prefix Examples/CamRelayExpo run android:validation-build
AVD_NAME=your_avd_name
./scripts/validate-android.sh "$AVD_NAME"
```

The script requires `adb`, `jq`, ImageMagick's `magick` or `convert`, `rg`, and `xmllint`. It checks front/back preview, photo capture, image and video orientation, source cadence and looping, live fixture switching, failed-selection preservation, app and AVD continuity after relay shutdown, unchanged AVD configuration, and explicit AVD cleanup.

On a headless Linux host, provide a private `XDG_RUNTIME_DIR`, configure hardware acceleration, and run the validator with `xvfb-run -a sh scripts/validate-android.sh "$AVD_NAME"`. The CI job sets these up for its dedicated AVD.

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
