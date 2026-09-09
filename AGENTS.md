# CamRelay repository instructions

Use this file for rules that apply while changing the repository. Use the linked documentation for product behavior, commands, architecture, and test procedures.

## Required reading

Read the documents related to the change before editing:

- User setup or workflows: [README.md](README.md) and [docs/usage.md](docs/usage.md)
- CLI commands, options, status, or errors: [docs/cli.md](docs/cli.md)
- iOS behavior or AVFoundation compatibility: [docs/ios.md](docs/ios.md)
- Android behavior or AVD control: [docs/android.md](docs/android.md)
- Components, timing, transport, concurrency, or cleanup: [docs/architecture.md](docs/architecture.md)
- Builds, examples, tests, or validation: [docs/development.md](docs/development.md)

Verify behavior against the relevant source and tests. Update the affected documentation when behavior changes.

## Product rules

- Apps under test must continue using standard platform camera APIs without CamRelay imports, linking, source changes, or special build settings.
- CamRelay operates on a virtual device, not an app. Do not inspect installed apps, select bundle identifiers, or add app-specific configuration.
- Named fixtures must switch without restarting apps. Fixture names and relay controls remain outside the app.
- Image and video fixtures must loop while the relay is running.
- Keep examples and generated fixtures domain-neutral.
- On iOS, preserve one stable camera format and continuous sample timestamps across selection, replay, pause, and resume. Choose the format from the highest-resolution supported fixture that can be decoded at startup.
- A failed fixture change must leave the active fixture intact.
- A slow or suspended iOS app must not block the shared timeline or other apps.
- iOS relay shutdown must remove all Simulator activation values and disconnect runtimes without terminating apps.
- Android relay shutdown must restore the idle camera scene and remove temporary media without stopping the AVD or apps. Only `emulator stop` shuts down the AVD.
- Android pause, resume, source-position reporting, and app delivery acknowledgements are unavailable.
- Errors must clearly identify ambiguous device selection, unsupported media, missing runtime files, activation failures, and platform control failures.

## Architecture rules

- Keep `CamRelayCore` portable, buildable on Linux, and free of Apple-only frameworks.
- Keep iOS and Android code in their platform modules.
- Implement camera compatibility as general platform behavior. Do not branch on a particular app or third-party SDK.
- Validation apps must use standard camera APIs and must not import or link CamRelay.
- Add a platform module only when its first working behavior is implemented.
- Transport changes must preserve deterministic playback, app sandbox isolation, bounded buffering, frame acknowledgement behavior, and reliable cleanup.
- Measure transport changes with representative 720p and 1080p fixtures.

## Development rules

- Inspect relevant files before editing and keep changes focused.
- Preserve existing conventions, formatting, architecture, and naming.
- Maintain backward compatibility unless a breaking change is explicitly requested.
- Add or update tests when behavior changes.
- Start with the smallest relevant test. Use the full validation list in [docs/development.md](docs/development.md) only for broad changes and release candidates.
- Record the exact commands run. Report affected configurations that were not tested as unverified.
- Documentation-only changes need content, link, and formatting checks. Builds are needed only when a documented command or behavior must be verified.
- Use `.build/debug/camrelay` in source-build documentation. Use `camrelay` only when the text clearly refers to an installed executable.
- Do not change generated files, lockfiles, migrations, or configuration unless the task requires it.
- Generated files under `.build` and generated Expo `ios` and `android` directories are not source files and must not be committed.
- Do not make unrelated fixes or refactors.

## Safety

- Never expose or commit secrets, credentials, tokens, private keys, or sensitive environment values.
- Do not commit, push, create or merge pull requests, publish, deploy, or perform destructive operations without explicit approval.
- Report test failures, lint errors, security concerns, breaking changes, and unresolved assumptions.
