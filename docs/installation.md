# Installation

Use a published CamRelay release tag to install the same CLI version in another QA repository. Release assets become available after the **CLI release binaries** workflow completes successfully.

## Release packages

For a release tag `vX.Y.Z`, the workflow attaches:

| Asset | Host |
| --- | --- |
| `camrelay-vX.Y.Z-macos-arm64.tar.gz` | Apple Silicon macOS 14 or newer |
| `camrelay-vX.Y.Z-macos-x86_64.tar.gz` | Intel macOS 14 or newer |
| `camrelay-vX.Y.Z-linux-x86_64.tar.gz` | Ubuntu 24.04 x86_64 or a compatible newer glibc host |
| `SHA256SUMS` | SHA-256 checksums for all three archives |

Each archive contains `bin/camrelay` and `VERSION`. macOS archives also contain `runtime/CamRelayRuntime.dylib`, with both arm64 and x86_64 iOS Simulator slices. Keep the `bin` and `runtime` directories together; the CLI finds its runtime when launched through `PATH` or an executable symlink. `CAMRELAY_RUNTIME_PATH` can override the runtime location.

The Linux executable links Swift statically, so the QA runner does not need a Swift installation. It still uses host system libraries and requires FFmpeg and an HTTP/2-enabled `/usr/bin/curl` for Android relays. See [Android requirements](android.md#requirements) for SDK, AVD, and headless-host setup. iOS relays require Xcode and an installed iOS 18 or newer Simulator runtime on macOS. macOS binaries and the bundled runtime use ad hoc signatures.

## Install in a repository

This example installs a pinned release in a GitHub Actions job. Replace the example `v0.1.0` with a published tag whose assets are ready. `GHA_NODEJS_TOKEN` must have read access to `cerebruminc/camrelay`.

```yaml
jobs:
  qa:
    runs-on: ubuntu-24.04 # Use macos-15 or macos-15-intel for iOS.
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7.0.1
      - name: Install pinned CamRelay
        env:
          GH_TOKEN: ${{ secrets.GHA_NODEJS_TOKEN }}
          CAMRELAY_TAG: v0.1.0 # Replace with published tag.
        shell: bash
        run: |
          case "$RUNNER_OS/$RUNNER_ARCH" in
            macOS/ARM64) target=macos-arm64 ;;
            macOS/X64) target=macos-x86_64 ;;
            Linux/X64) target=linux-x86_64 ;;
            *) echo "Unsupported CamRelay host: $RUNNER_OS/$RUNNER_ARCH" >&2; exit 1 ;;
          esac
          archive="camrelay-$CAMRELAY_TAG-$target.tar.gz"
          download_dir="$RUNNER_TEMP/camrelay-download"
          install_dir="$RUNNER_TEMP/camrelay"
          mkdir -p "$download_dir" "$install_dir"
          gh release download "$CAMRELAY_TAG" --repo cerebruminc/camrelay \
            --pattern "$archive" --pattern SHA256SUMS --dir "$download_dir"
          cd "$download_dir"
          awk -v name="$archive" '$2 == name { print }' SHA256SUMS > "$archive.sha256"
          test -s "$archive.sha256"
          if [ "$RUNNER_OS" = macOS ]; then
            shasum -a 256 --check "$archive.sha256"
          else
            sha256sum --check "$archive.sha256"
          fi
          tar -xzf "$archive" -C "$install_dir"
          test "$("$install_dir/bin/camrelay" --version)" = "camrelay ${CAMRELAY_TAG#v}"
          echo "$install_dir/bin" >> "$GITHUB_PATH"
      - name: Check installed CLI
        run: camrelay --version
```

On Linux, install `ffmpeg` and `curl` with `sudo apt-get update && sudo apt-get install -y ffmpeg curl` before running Android relays. The QA repository remains responsible for its Android SDK, AVD, Simulator, and app setup.

Use `camrelay` in subsequent steps. The [CI usage example](usage.md#use-camrelay-in-ci) shows how to start a relay, wait for readiness, switch fixtures, and stop it; replace its source-build executable path with `camrelay`.

## Retry release asset builds

Open **Actions → CLI release binaries → Run workflow**, select `master`, and enter the existing published tag. You can also rerun failed jobs on the original run.

Every build checks out the commit resolved from that release tag, checks the CLI version, extracts and runs the package outside the source checkout, and verifies architecture and runtime dependencies. The workflow attaches assets only after all three packages pass. Retrying replaces assets with matching names, including `SHA256SUMS`.
