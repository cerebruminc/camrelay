# Usage

Use this guide to build CamRelay, run fixtures, and control a session. The [CLI reference](cli.md) lists every command and option.

## Build from source

CamRelay's Swift package targets macOS 14 or newer and requires Swift 6.2 or newer.

Build the debug CLI from the repository root:

```sh
swift build
```

The executable is `.build/debug/camrelay`. Rebuild after changing Swift source.

iOS support also needs the Simulator runtime:

```sh
./scripts/build-runtime.sh
```

This creates `.build/runtime/CamRelayRuntime.dylib` with arm64 and x86_64 Simulator slices. Android runs do not use this runtime.

For an optimized CLI build:

```sh
swift build -c release
```

The release executable is `.build/release/camrelay`. It uses the same separately built iOS runtime.

## Run one fixture

iOS is the default platform:

```sh
.build/debug/camrelay path/to/fixture.mp4
```

Boot exactly one iOS Simulator before running the command. Launch or relaunch the app after CamRelay reports that the relay is ready.

For Android, first start a stopped AVD with CamRelay camera support:

```sh
AVD_NAME=your_avd_name
.build/debug/camrelay emulator start --platform android --avd "$AVD_NAME"
.build/debug/camrelay --platform android --avd "$AVD_NAME" path/to/fixture.mp4
```

See [iOS Simulator](ios.md) and [Android Emulator](android.md) for setup and shutdown details.

## Supported fixtures

Supported image extensions:

- PNG
- JPEG and JPG
- HEIC and HEIF
- TIFF and TIF
- BMP

Supported video extensions:

- MP4
- MOV
- M4V

CamRelay validates the path and extension before starting. Decoding failures are reported separately.

## Run named fixtures

Use named fixtures when a test needs to switch its camera input without restarting the relay or app:

```sh
./scripts/generate-fixtures.sh

.build/debug/camrelay run --session demo \
  --fixture colors=.build/fixtures/colors.mp4 \
  --fixture pattern=.build/fixtures/checkerboard.png \
  --fixture motion=.build/fixtures/moving-shapes.mp4 \
  --initial colors
```

Fixture names are labels for CLI control. They are never sent to the app.

From another terminal:

```sh
.build/debug/camrelay select pattern --session demo
.build/debug/camrelay next --session demo
.build/debug/camrelay replay --session demo
.build/debug/camrelay status --session demo --json
.build/debug/camrelay stop --session demo
```

Selection, replay, next, and previous start at the beginning of the selected fixture. Next and previous wrap around the fixture list. If a replacement fixture cannot be prepared, CamRelay keeps the previous fixture active.

On iOS, `--paused` can hold the replacement's first frame and `play` or `pause` can control source playback. Camera samples and timestamps continue while the source is paused. The Android Emulator does not provide pause or resume for environment-camera media.

## Generated fixtures

`./scripts/generate-fixtures.sh` creates reusable fixtures under `.build/fixtures`:

| Fixture | Purpose |
| --- | --- |
| `colors.mp4` | 320×240, 15 fps red/green/blue cycle |
| `checkerboard.png` | 480×640 static aspect-fitting pattern |
| `moving-shapes.mp4` | 1280×720, 24 fps moving shapes |
| `orientation.png` | Portrait quadrant orientation check |
| `orientation-rotate90.mp4` | Rotation-metadata orientation check |

The files are generated locally and are not source files.

For an iOS named-fixture session, the highest-resolution supported fixture that can be decoded at startup fixes the camera dimensions for the session. If dimensions tie, the higher frame rate wins. In the example above, `moving-shapes.mp4` sets a 1280×720, 24 fps output even though `colors.mp4` is initially selected. Other sources are fitted without cropping.

On Android, CamRelay prepares each fixture for the Emulator's environment-camera viewport. The Emulator owns the camera format and loop.

## Interactive controls

When the relay runs in an interactive terminal:

| Key | Action |
| --- | --- |
| `1`-`9` | Select a fixture by list position |
| `n` | Select next fixture |
| `b` | Select previous fixture |
| `r` | Replay current fixture |
| Space | Pause or play on iOS |
| `q` | Stop the relay |

Use `--no-interactive` to disable terminal input. It is disabled automatically when standard input is not a terminal.

## Use CamRelay in CI

Run the relay in the background, wait until it can accept commands, then control it from the test runner:

```sh
.build/debug/camrelay run --session demo --no-interactive --paused \
  --fixture colors=.build/fixtures/colors.mp4 \
  --fixture pattern=.build/fixtures/checkerboard.png &
relay_pid=$!
trap '.build/debug/camrelay stop --session demo >/dev/null 2>&1 || true; wait "$relay_pid"' EXIT

.build/debug/camrelay wait --session demo --timeout 30s --json
# Launch the app and navigate to its camera with the test runner.
.build/debug/camrelay select pattern --session demo --paused --wait-for-frame --timeout 10s
# Capture or inspect the app result with the test runner.
```

`wait` confirms that the named relay can accept commands. On iOS, `--wait-for-frame` also requires a connected capture receiver and waits for every currently connected receiver to acknowledge the new playback generation. It does not prove that an app callback, photo capture, or rendered UI has completed.

Android does not support `--paused` or `--wait-for-frame`. Omit those options and add `--platform android --avd "$AVD_NAME"` to the run command.

See [CLI reference](cli.md) for timeouts, JSON output, and errors.

## Stop and clean up

Ctrl-C, SIGTERM, `q`, and `camrelay stop` all stop a relay.

- On iOS, shutdown removes CamRelay's values from the Simulator launch environment and disconnects runtimes. It does not terminate apps.
- On Android, shutdown restores the AVD's idle environment-camera scene and removes temporary media. It leaves the AVD and apps running.

Stop an Android AVD separately:

```sh
.build/debug/camrelay emulator stop --platform android --avd "$AVD_NAME"
```
