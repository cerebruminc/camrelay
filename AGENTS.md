# CamRelay Repository Guidelines

This file contains durable technical guidance for contributors and automated development agents working in this repository. Keep it factual, current, and focused on product behavior, architecture, platform constraints, and repeatable validation.

## Product

CamRelay is a CLI for supplying deterministic image or video fixtures as the camera input seen by apps running in virtual mobile devices.

```sh
camrelay path/to/fixture.mp4
camrelay path/to/fixture.png
```

The current platform is iOS Simulator on macOS. Shared code must remain portable so additional virtual-device backends can be supported without depending on Apple-only frameworks.

## Product Requirements

- The app under test must not require source changes, additional imports, SDK integration, linking, or special build configuration.
- Apps must continue to use standard platform camera APIs.
- Camera compatibility must cover common AVFoundation surfaces as a general platform capability rather than being tailored to one app or SDK.
- The CLI must detect an unambiguous booted target, enable the relay throughout that Simulator, loop the supplied fixture, and clean up all session state when it terminates.
- The CLI must not inspect installed apps, select bundle identifiers, or require app-specific configuration.
- Errors must clearly explain ambiguous Simulator selection, unsupported media, missing runtime components, and Simulator activation failures.
- Platform-specific code must remain isolated from the portable core.

## Architecture

- `CamRelayCLI`: argument parsing, target detection, lifecycle, and human-readable errors.
- `CamRelayCore`: platform-neutral models and orchestration. It must remain buildable on Linux.
- `CamRelayIOS`: macOS-only iOS Simulator adapter and Apple media decoding.
- `CamRelayRuntime`: Objective-C runtime loaded into an iOS Simulator app to expose and deliver a synthetic camera feed.
- `CamRelayProbe`: validation app that uses standard AVFoundation APIs and has no dependency on CamRelay.
- `CamRelayExpo`: Expo development-build example that validates the preview through `react-native-vision-camera`.

Add a new platform module when its first working behavior is implemented. Do not add empty modules solely to represent planned architecture.

## Application Integration

CamRelay requires no changes to the app under test. Apps discover and consume the synthetic camera through standard AVFoundation APIs.

The iOS runtime is enabled in the booted Simulator's launch environment for the lifetime of the relay. The CLI does not enumerate, select, launch, or terminate individual apps. Every app process launched or relaunched while CamRelay is active inherits the runtime, and multiple apps can consume the same fixture concurrently. Apps already running when the relay starts require a relaunch because an existing process cannot inherit a changed launch environment.

Ctrl-C and SIGTERM remove every relay value from the Simulator launch environment and stop the frame server. Control connections notify already-loaded runtimes that the relay ended without transferring app lifecycle ownership to the CLI. Signal handling and cleanup must remain reliable when multiple apps and worker threads are active.

## Camera Compatibility

The compatibility layer should support the common AVFoundation surfaces used by camera applications, including:

- Camera discovery and device properties
- Device input and capture-session configuration
- Formats, frame-rate ranges, and capture connections
- Video-data, photo, and movie-file outputs
- Preview layers
- Focus, exposure, and related camera controls

Compatibility must be validated across representative applications and API combinations. The validation app provides a focused baseline but does not define the full compatibility boundary.

The current implementation provides front and back wide-angle camera discovery, fixture-derived formats and frame-rate ranges, device input ports, capture-session configuration, capture connections, and running-state notifications. It delivers BGRA and bi-planar YUV video samples, renders preview layers, captures JPEG photos, records H.264 movies, and detects QR metadata. Common focus, exposure, white-balance, zoom, orientation, mirroring, and stabilization properties are also available.

Depth data, audio capture, raw photos, and non-QR metadata are not currently synthesized. Camera-control configuration is accepted for API compatibility but does not modify the fixture pixels. New compatibility behavior must remain general to the platform and must not be conditioned on a particular application or third-party SDK.

## Frame Transport

Decoded BGRA frames travel from the macOS CLI to app runtimes over loopback TCP connections. Each client begins with a one-byte role: `C` establishes a control connection and receives a one-byte acknowledgement, while `F` establishes a frame connection. A frame connection then receives five big-endian `UInt32` header values: magic `CRF2`, width, height, bytes per row, and frames per second. Every fixed-size frame payload is preceded by two big-endian `UInt64` values containing its source presentation time and duration in nanoseconds. The server schedules frames against an absolute monotonic deadline and broadcasts one fixture timeline through bounded per-client writers. Writers replace queued frames when necessary so a slow or suspended app cannot block active apps, create unbounded memory growth, or slow the fixture timeline.

The transport keeps fixture paths outside the app sandbox and media decoding outside the target process. Any transport replacement must preserve deterministic playback, app isolation, cleanup behavior, and portability of the core module. Measure realistic 720p and 1080p workloads before changing the transport.

## Validation

The validation app must use standard AVFoundation camera discovery and capture APIs and must not import or link CamRelay-specific code.

Functional validation scenarios:

1. Without CamRelay, the validation app reports that no camera is available.
2. With a static color image, it receives repeated frames of that color and an increasing frame counter.
3. With a changing-color video, it receives changing frames, the counter increases, and playback loops.
4. The same session configures video-data, photo, movie-file, metadata, preview, format, port, and connection surfaces successfully.
5. Photo capture returns image data and movie recording produces a playable file without an error.
6. Two apps with different bundle identifiers can receive the same relay concurrently without app selection or relay reconfiguration.
7. Suspending or slowing one connected app does not interrupt frame delivery, looping, or output capture in another app.
8. Ctrl-C and SIGTERM remove the Simulator-wide activation, disconnect every client, and leave app lifecycle under Simulator control.
9. Runtime and validation-app artifacts contain both arm64 and x86_64 Simulator slices, and each runtime slice loads in a matching app process.
10. The Expo example discovers the synthetic cameras, starts its VisionCamera preview, and visibly renders changing video frames.

### Validation Scope

Start with the smallest test or check that directly covers the changed behavior. Do not run unrelated builds, Simulator scenarios, architectures, media paths, or output checks for a narrowly scoped change.

- Documentation-only changes require review of the affected text plus applicable formatting or link checks. They do not require builds or Simulator runs unless the documented command or behavior must be verified.
- Isolated core or CLI changes require the relevant filtered test or test target first. Expand to the full unit-test suite only when shared behavior or interfaces may be affected.
- Changes to one camera surface or media path require the corresponding probe scenario first. Add other surfaces or fixture types only when they share the changed implementation.
- Changes confined to the Expo example start with `npm run typecheck`. Run its Simulator scenario only when native camera behavior or the displayed video path changes, and run the native probe first only when the underlying AVFoundation runtime also changes.
- Architecture or build-script changes require checks for the affected artifacts and architectures, without requiring unrelated camera scenarios.
- Simulator activation, cleanup, transport, concurrency, or shared frame-pipeline changes require the affected end-to-end scenarios because they can influence multiple apps or outputs.

Expand validation only when the change has a wider impact, a focused check exposes a possible regression elsewhere, or a full regression run is explicitly requested. Report any affected configuration that could not be checked as unverified.

### Complete Validation Matrix

Run the complete validation matrix for release candidates and changes that span multiple camera surfaces, media paths, architectures, or lifecycle paths. It is not the default for documentation-only, isolated, or otherwise narrow changes.

- arm64 and x86_64 app processes
- Multiple app bundles connected concurrently without app selection
- Slow or suspended clients isolated from active clients
- Static-image and changing-video fixtures
- Video frames, preview, photo capture, movie recording, formats, ports, and connections
- Video color changes and at least one confirmed playback loop
- Ctrl-C and SIGTERM cleanup
- Universal-artifact architecture and code-signature checks
- The full unit-test suite on each supported host architecture available in the development environment

If a complete matrix run is required but an entry cannot be run, report it as unverified and do not claim full validation.

## Development Commands

```sh
swift test
swift run camrelay --help
./scripts/build-runtime.sh
./scripts/build-probe.sh
./scripts/generate-fixtures.sh
cd Examples/CamRelayExpo && npm run typecheck
```

The build and fixture scripts create disposable artifacts under `.build`. Generated artifacts are not source files and must not be committed.

## Platform Constraints

- Runtime and validation-app build scripts emit universal arm64 and x86_64 iOS Simulator binaries.
- x86_64 Simulator execution on Apple Silicon requires the macOS translation component.
- Video preferred-transform metadata is not applied yet, so some portrait recordings may appear rotated.
- Apple-only frameworks must remain confined to the iOS adapter and runtime targets.

## Working Rules

- Inspect relevant files before editing and keep changes focused.
- Preserve existing project conventions, formatting, architecture, and naming.
- Start with the smallest relevant test or check and validate only the behavior and supported configurations affected by the change. Use the complete matrix only under the conditions defined above.
- Record exact validation commands and never claim that an unexecuted check passed.
- Do not modify generated files, lockfiles, migrations, or configuration unless required by the task.
- Do not expose secrets, credentials, tokens, private keys, or sensitive environment values.
- Do not commit, push, publish, deploy, merge, or perform destructive operations without explicit authorization.
- Report test failures, lint errors, security concerns, breaking changes, and unresolved assumptions.
