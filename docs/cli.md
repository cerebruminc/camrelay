# CLI reference

Examples in this document use an installed `camrelay` executable. For a source build, replace it with `.build/debug/camrelay`.

## Command forms

```text
camrelay [--platform ios|android] <media-file>
camrelay run [--platform ios|android] --session <name> --fixture <name=path> [--fixture <name=path> ...]
camrelay emulator start|stop --platform android [--avd <name>]
camrelay select <fixture-name> [--session <name>] [--paused] [--wait-for-frame]
camrelay replay|next|previous [--session <name>] [--paused] [--wait-for-frame]
camrelay pause|play [--session <name>] [--wait-for-frame]
camrelay status|wait|stop [--session <name>] [--json]
```

`camrelay --help` prints command help. `camrelay --version` prints the current version string.

## Start a relay

A positional media path is shorthand for a single-fixture run:

```sh
camrelay fixture.mp4
camrelay --platform android --avd "$AVD_NAME" fixture.mp4
```

Use `run` to name fixtures or the session:

```sh
camrelay run --session demo \
  --fixture still=checkerboard.png \
  --fixture video=colors.mp4 \
  --initial still
```

Positional paths can also be used with `run`. CamRelay assigns them the names `fixture-1`, `fixture-2`, and so on.

### Run options

| Option | Meaning |
| --- | --- |
| `--platform ios|android` | Select the platform. The default is `ios`. |
| `--avd <name>` | Select an Android AVD. It is valid only with `--platform android`. |
| `--session <name>` | Set the session name. The default is `default`. |
| `--fixture <name=path>` | Add a named fixture. Repeat for multiple fixtures. |
| `--initial <name>` | Select the first fixture. The default is the first listed fixture. |
| `--paused` | Hold the initial frame on iOS. Unsupported on Android. |
| `--no-interactive` | Disable terminal controls. This happens automatically without a TTY. |
| `--` | Treat all remaining run arguments as positional fixture paths. |

At least one fixture is required. Fixture names must be unique within the run.

Session, fixture, and AVD names must contain 1-48 letters, digits, underscores, or hyphens and cannot start with a hyphen.

## Manage an Android Emulator

```sh
camrelay emulator start --platform android [--avd <name>]
camrelay emulator stop --platform android [--avd <name>]
```

These commands currently support only Android. If `--avd` is omitted, CamRelay selects the AVD automatically only when exactly one is available.

`emulator start` requires the selected AVD to be stopped and launches it with front and back environment cameras. `emulator stop` shuts down the selected AVD. Starting or stopping a relay does not start or stop the emulator.

## Control a relay

Control commands address a running session. They use `default` unless `--session` is supplied.

| Command | Behavior |
| --- | --- |
| `select <name>` | Select a named fixture at its beginning. |
| `replay` | Restart the current fixture from its beginning. |
| `next` | Select the next fixture, wrapping at the end. |
| `previous` | Select the previous fixture, wrapping at the beginning. |
| `pause` | Hold the iOS source position while camera samples continue. |
| `play` | Resume iOS source playback. |
| `status` | Return the current relay state. |
| `wait` | Retry until the session endpoint is ready or the timeout expires. |
| `stop` | Stop the relay after replying to the caller. |

Android supports `select`, `replay`, `next`, `previous`, `status`, `wait`, and `stop`. It does not support `pause` or `play`.

### Control options

| Option | Meaning |
| --- | --- |
| `--session <name>` | Address a named session. |
| `--paused` | Leave a select, replay, next, or previous result paused on iOS. |
| `--wait-for-frame` | On iOS, wait for every connected receiver to acknowledge the new generation. |
| `--timeout <seconds>` | Set the readiness or delivery timeout. Accepts a number with an optional `s` suffix; range is greater than 0 through 300 seconds. Default: 10 seconds. |
| `--json` | Write a structured status or error response. |

`--wait-for-frame` is valid for playback commands, including `pause` and `play`, but not for `status` or `stop`. Android rejects it because the Emulator environment camera does not expose delivery acknowledgements.

## Wait for a relay or frame

`camrelay wait` waits until the named relay can accept commands. It does not require an app camera to be open.

Each iOS selection, replay, and actual pause/play transition advances a playback generation. With `--wait-for-frame`, a command succeeds after:

1. At least one frame receiver is connected.
2. Every receiver connected at that point acknowledges the generation.

A receiver represents a running synthetic capture session, not an installed app. An acknowledgement means the runtime accepted the frame and made it available to the camera outputs. App callbacks, photo completion, and UI rendering still need their own assertions.

A suspended receiver can cause a timeout without blocking active receivers. A timeout does not undo the selected fixture. Query `status --json` before retrying a non-idempotent command such as `next`.

## Status and JSON

Plain-text status shows the session, selected fixture, and play or pause state. Use `--json` to read all status fields.

A successful JSON response contains a `status` object. If a running relay rejects a command, the response contains its current `status` and an `error` string. Argument and connection failures can contain only `error`. Status fields are:

| Field | Meaning |
| --- | --- |
| `session` | Session name |
| `simulator` | Selected virtual device display name |
| `simulatorID` | Simulator UDID or Android emulator serial |
| `fixtures` | Ordered fixture names |
| `selected` | Current fixture name |
| `paused` | Whether source playback is paused |
| `generation` | Playback generation |
| `positionSeconds` | Source position since selection, including loops |
| `connectedReceivers` | Current iOS frame receivers |
| `acknowledgedReceivers` | Receivers that acknowledged the current generation |
| `width`, `height` | iOS session output dimensions |
| `framesPerSecond` | iOS session output rate |
| `error` | Current decoder error, if any |

Android JSON status includes the selected fixture and generation. `paused` is always false, and source position, receiver counts, output dimensions, and frame rate are zero because the Emulator does not provide them to CamRelay.

## Failure behavior

- Invalid arguments exit with status 2.
- Operational failures exit with status 1.
- A fixture that fails preparation does not replace the active source.
- An iOS decoder failure during playback holds the last valid frame, pauses the source clock, and appears in `status.error`.
- A command may commit before its response connection is lost. Check status before retrying commands such as `next`.
- Only one relay can own an iOS Simulator at a time, even when different session names are used.
