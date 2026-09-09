# iOS Simulator

On iOS, CamRelay exposes synthetic front and back cameras to apps running in one booted Simulator. Apps use standard AVFoundation APIs and do not link to CamRelay.

## Requirements

- macOS 14 or newer
- Swift 6.2 or newer
- Xcode with an iOS Simulator runtime
- Exactly one booted Simulator when starting a relay

The host CLI is currently built and tested on Apple Silicon. The injected runtime contains arm64 and x86_64 Simulator slices. Running an x86_64 Simulator app on Apple Silicon requires the macOS translation component.

## Build

From the repository root:

```sh
./scripts/build-runtime.sh
swift build
```

The runtime script creates `.build/runtime/CamRelayRuntime.dylib`. The debug CLI is `.build/debug/camrelay`.

## Start a relay

Boot exactly one Simulator, then run:

```sh
.build/debug/camrelay path/to/fixture.mp4
```

After CamRelay reports that the session is ready, launch or relaunch the app. Apps that were already running must be relaunched because an existing process cannot inherit a changed Simulator launch environment.

The camera feed is enabled for the whole Simulator:

- CamRelay does not inspect installed apps or select a bundle identifier.
- Every app launched while the relay is active inherits the runtime.
- Multiple app processes can receive the same fixture playback.
- Fixture changes do not require another app relaunch.

Only one relay can own a Simulator at a time.

## Fixture behavior

Images repeat at 30 frames per second. Videos use their source timestamps for pacing and loop without resetting the continuous camera timeline. CamRelay applies image orientation and video preferred-transform metadata before fitting pixels into the session format.

For a named-fixture session, CamRelay opens the fixtures at startup and chooses one stable camera format:

1. The supported, decodable fixture with the largest pixel count determines the dimensions.
2. If dimensions tie, the fixture with the higher frame rate wins.
3. `--initial` changes the first selected source, not the output format.

Other fixtures are scaled to fit the stable dimensions without cropping; unused pixels are black. Pausing, replaying, and changing fixtures do not reset camera timestamps.

If CamRelay cannot load a fixture during selection, the active fixture remains unchanged. A decoder failure during playback holds the last valid frame and appears in session status.

## Playback control

iOS supports all CamRelay playback commands:

- `select`
- `replay`
- `next` and `previous`
- `pause` and `play`
- `status`, `wait`, and `stop`

`--paused` is available for run, select, replay, next, and previous. `--wait-for-frame` waits for connected runtimes to acknowledge the new frame.

See the [CLI reference](cli.md) for command syntax and details about frame acknowledgements.

## Camera compatibility

The runtime currently provides these AVFoundation features:

- Front and back built-in wide-angle camera discovery
- Default-device and unique-identifier lookup
- Video authorization responses
- Device formats and frame-rate ranges
- Device inputs, input ports, capture-session collections, and capture connections
- Session presets and running-state notifications
- Packed BGRA, full-range bi-planar YUV, and video-range bi-planar YUV video-data output
- Video preview layers
- JPEG photo capture and metadata customization
- H.264 movie-file recording
- QR metadata output
- Common focus, exposure, white-balance, zoom, orientation, mirroring, and stabilization properties

Orientation and mirroring affect converted video-data samples. Focus, exposure, white balance, stabilization, and zoom settings are accepted and can be read back, but they do not alter fixture pixels.

The same compatibility behavior applies to every app and camera SDK.

## Stop and cleanup

Ctrl-C, SIGTERM, terminal `q`, and `camrelay stop` all stop the relay in the same way.

CamRelay removes its values from the Simulator launch environment, closes its connections, and notifies loaded runtimes that the relay ended. It does not terminate app processes.

Apps launched after cleanup return to the Simulator's normal camera behavior.

## Current limitations

- The synthetic camera exposes one stable format for a relay session.
- Audio capture, depth data, raw photos, and metadata types other than QR are not synthesized.
- Photo metadata replacement is supported, but replacement thumbnails and auxiliary depth or matte images are not.
- Camera-control configuration other than orientation and mirroring does not change the fixture pixels.
- Raw BGRA transport over loopback TCP can use substantial bandwidth at high resolutions.
