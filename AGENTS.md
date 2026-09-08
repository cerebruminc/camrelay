# CamRelay Repository Guidelines

This file contains durable technical guidance for contributors and automated development agents working in this repository. Keep it factual, current, and focused on product behavior, architecture, platform constraints, and repeatable validation.

## Product

CamRelay is a CLI for supplying deterministic image or video fixtures as the camera input seen by apps running in virtual mobile devices.

After building the runtime and CLI, source-build commands run from the repository root:

```sh
.build/debug/camrelay path/to/fixture.mp4
.build/debug/camrelay path/to/fixture.png
.build/debug/camrelay --platform android --avd Pixel_10 path/to/fixture.mp4
```

The iOS Simulator backend is complete. Android Emulator supports image and video fixtures, live named-fixture switching, replay, and owned AVD lifecycle. Shared code must remain portable without depending on Apple-only frameworks.

## Product Requirements

- The app under test must not require source changes, additional imports, SDK integration, linking, or special build configuration.
- Apps must continue to use standard platform camera APIs.
- Camera compatibility must cover common AVFoundation surfaces as a general platform capability rather than being tailored to one app or SDK.
- The CLI must detect an unambiguous booted target, enable the relay throughout that Simulator, loop the supplied fixture, and clean up all session state when it terminates.
- The CLI must not inspect installed apps, select bundle identifiers, or require app-specific configuration.
- Named fixtures must switch within the running relay without restarting apps. Terminal keys and CI commands use the same controller; the app never selects fixtures or knows about the relay.
- Keep examples and fixture names domain-neutral. Use locally generated patterns and motion to demonstrate playback and capture without prescribing an app workflow.
- Preserve the initial camera format and continuous sample timestamps across selection, replay, pause, and resume. Failed source preparation must leave the active source intact.
- Errors must clearly explain ambiguous Simulator selection, unsupported media, missing runtime components, and Simulator activation failures.
- Platform-specific code must remain isolated from the portable core.

## Architecture

- `CamRelayCLI`: argument parsing, target detection, lifecycle, and human-readable errors.
- `CamRelayCore`: platform-neutral models and orchestration. It must remain buildable on Linux.
- `CamRelayIOS`: macOS-only iOS Simulator adapter and Apple media decoding.
- `CamRelayAndroid`: Android SDK discovery, AVD lifecycle, environment-camera activation, and authenticated emulator control.
- `CamRelayRuntime`: Objective-C runtime loaded into an iOS Simulator app to expose and deliver a synthetic camera feed.
- `CamRelayProbe`: validation app that uses standard AVFoundation APIs and has no dependency on CamRelay.
- `CamRelayExpo`: Expo development-build example that validates the preview through `react-native-vision-camera`.

Add a new platform module when its first working behavior is implemented. Do not add empty modules solely to represent planned architecture.

## Application Integration

CamRelay requires no changes to the app under test. Apps discover and consume the synthetic camera through standard AVFoundation APIs.

The iOS runtime is enabled in the booted Simulator's launch environment for the lifetime of the relay. The CLI does not enumerate, select, launch, or terminate individual apps. Every app process launched or relaunched while CamRelay is active inherits the runtime, and multiple apps can consume the same fixture concurrently. Apps already running when the relay starts require a relaunch because an existing process cannot inherit a changed launch environment.

Ctrl-C and SIGTERM remove every relay value from the Simulator launch environment and stop the frame server. Control connections notify already-loaded runtimes that the relay ended without transferring app lifecycle ownership to the CLI. Signal handling and cleanup must remain reliable when multiple apps and worker threads are active.

The Android backend launches a stopped AVD with front and back environment cameras. It uses the emulator's ephemeral, token-protected localhost gRPC endpoint, temporarily updates the AVD's `environment.ini`, and switches image or video fixtures through the same endpoint. Stopping the relay shuts down only the emulator process it launched, then restores the prior file. Android apps continue to use standard camera APIs without CamRelay integration. Pause/play and app delivery acknowledgements are not available through this emulator camera path.

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

Decoded BGRA frames travel from the macOS CLI to app runtimes over loopback TCP connections. Each client begins with a one-byte role: `C` establishes a lifetime connection and receives a one-byte acknowledgement, while `F` establishes a frame connection. A frame connection receives five big-endian `UInt32` header values: magic `CRF3`, width, height, bytes per row, and frames per second. Each fixed-size frame payload is preceded by three big-endian `UInt64` values: playback generation, continuous camera presentation time, and duration in nanoseconds. The runtime acknowledges a received generation with a big-endian `UInt64` on the frame connection. `--wait-for-frame` requires at least one receiver and acknowledgement from every currently connected receiver; it does not assert app capture or UI completion.

The initial fixture fixes the output format. The playback engine samples each selected source at that output rate and fits its pixels without cropping. A separate source clock supports pausing and replay while camera timestamps advance. The server schedules against an absolute monotonic deadline and broadcasts through bounded per-client writers. Writers replace queued frames so a slow or suspended app cannot block active apps, create unbounded memory growth, or slow the timeline.

Management commands use length-prefixed JSON over a per-user Unix socket, separate from runtime lifetime and frame connections. Session and Simulator leases prevent competing owners. Keep the control directory private, validate socket ownership, and only replace stale sockets while holding the session lease.

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
11. Named image and video fixtures with different dimensions and frame rates switch without relaunching either example app. Use generated colors, checkerboard, and moving-shapes fixtures. Capture checks include JPEG metadata export and front/back camera reconfiguration in both directions.
12. Replay, pause, resume, readiness, delivery acknowledgements, failed selection, and stop work through CLI commands. Paused feeds continue delivering samples; failed selection preserves the previous source.

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
- Live fixture switching, stable camera format and timestamps, and repeated captures across camera switches
- Named-session control, delivery timeouts, failure preservation, and terminal controls
- Ctrl-C and SIGTERM cleanup
- Universal-artifact architecture and code-signature checks
- The full unit-test suite on each supported host architecture available in the development environment

If a complete matrix run is required but an entry cannot be run, report it as unverified and do not claim full validation.

## Development Commands

Build the runtime and CLI once from the repository root, then reuse the executable for subsequent commands. Rebuild after source changes. Documentation should use `.build/debug/camrelay` consistently for source builds; an installed executable can be invoked as `camrelay`.

```sh
./scripts/build-runtime.sh
swift build
.build/debug/camrelay --help
swift test
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
