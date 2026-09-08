# CamRelay Expo example

This example is an Expo development build with a live camera preview, photo capture, and front/back camera switching through `react-native-vision-camera`. It has no fixture list or required capture sequence.

It cannot run in Expo Go because VisionCamera contains native code. The first run generates and builds a local iOS or Android project; later JavaScript-only changes can use the existing development build.

## Install

```sh
cd Examples/CamRelayExpo
npm install
```

The install applies `patches/react-native-vision-camera+4.7.3.patch`. On iOS, VisionCamera normally rejects every Simulator at compile time. The patch keeps that rejection when no video device exists, permits configuration when CamRelay exposes a discoverable synthetic camera, and avoids configuring the unused audio session because this example disables audio. Android uses VisionCamera without that Simulator-specific path.

## iOS build

Boot one iOS Simulator, then run:

```sh
npm run ios
```

This generates the disposable `ios` directory, builds the native development app, installs it, and starts Metro. The generated native directory is ignored by Git.

## Android build

For local development with an already running emulator:

```sh
npm run android
```

For the repeatable repository validation, build a release APK with its JavaScript embedded:

```sh
npm run android:validation-build
```

The generated `android` directory is disposable and ignored by Git.

## Verify CamRelay video

In a separate terminal at the repository root, build CamRelay's injected runtime and CLI once:

```sh
./scripts/build-runtime.sh
swift build
```

Keep that terminal at the repository root for all CamRelay commands. They reuse the built executable; rebuild after changing its source. If `camrelay` is installed on your path, use it in place of `.build/debug/camrelay`.

Start CamRelay with a video fixture:

```sh
.build/debug/camrelay /absolute/path/to/fixture.mp4
```

For Android, select a stopped AVD, start it once, then attach a relay:

```sh
CAMRELAY_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
"$CAMRELAY_SDK/emulator/emulator" -list-avds
AVD_NAME=your_avd_name
.build/debug/camrelay emulator start --platform android --avd "$AVD_NAME"
.build/debug/camrelay --platform android --avd "$AVD_NAME" /absolute/path/to/fixture.mp4
```

Stopping the relay leaves the emulator and app running. When finished with the AVD, stop it explicitly:

```sh
.build/debug/camrelay emulator stop --platform android --avd "$AVD_NAME"
```

Relaunch **CamRelay Expo** after the relay starts. The example must show:

- The selected synthetic camera name.
- `Camera: active`.
- `Preview: active`.
- Visible motion as the video fixture advances and loops.

Use the on-screen button to exercise both front and back synthetic cameras. If CamRelay is not active when the app launches, the example instead explains that no camera was discovered.

For later runs, keep the installed native app and start Metro from `Examples/CamRelayExpo` with:

```sh
npm start
```

## Taking and reviewing photos

The live preview has separate controls for taking a photo and switching cameras. Controls show when they are unavailable, and a progress indicator appears during capture.

Each successful capture opens the actual photo in a full-screen review, with its capture number, camera position, and dimensions. Choose **Back to camera** to continue. The live view keeps a last-photo thumbnail; tap it to reopen the review without taking another photo. Photos are stored in the app's temporary files, not the system photo library.

A failed capture shows an error and leaves the last successful photo available. Camera errors offer a retry action. If camera access is denied, the app provides a button to open Settings. The camera pauses while the app is in the background.

## Multiple fixtures from the terminal

After building the runtime and CLI above, generate the fixtures and start one relay from the repository root:

```sh
./scripts/generate-fixtures.sh
.build/debug/camrelay run --session demo --paused \
  --fixture colors=.build/fixtures/colors.mp4 \
  --fixture pattern=.build/fixtures/checkerboard.png \
  --fixture motion=.build/fixtures/moving-shapes.mp4
```

Launch the example after the relay is ready. Use its photo and camera-switch buttons, or invoke the same handlers with Simulator URLs. Run these commands from a second terminal at the repository root:

```sh
xcrun simctl launch booted org.camrelay.expo
.build/debug/camrelay select colors --session demo --paused --wait-for-frame
xcrun simctl openurl booted org.camrelay.expo://capture
# Wait for the photo review, then return to the camera.
xcrun simctl openurl booted org.camrelay.expo://close-photo
xcrun simctl openurl booted org.camrelay.expo://switch-camera
# Wait for Camera: active before the next capture.
.build/debug/camrelay select pattern --session demo --paused --wait-for-frame
xcrun simctl openurl booted org.camrelay.expo://capture
# Wait for the photo review, then return to the camera.
xcrun simctl openurl booted org.camrelay.expo://close-photo
xcrun simctl openurl booted org.camrelay.expo://switch-camera
.build/debug/camrelay select motion --session demo --paused --wait-for-frame
# Wait for Camera: active before capturing.
xcrun simctl openurl booted org.camrelay.expo://capture
# Wait for the photo review before returning to the live preview.
xcrun simctl openurl booted org.camrelay.expo://close-photo
.build/debug/camrelay play --session demo
```

The app logs `[CameraExample] <camera-position> captured <width>x<height> path=<saved-photo>` after each photo, then `[CameraExample] photo <number> review loaded` when the image is displayed. `review-photo` reopens the latest photo, `close-photo` returns to the camera, and `retry-camera` retries camera setup. Capture and camera switching are unavailable while the review is open. These test URLs invoke the example's normal UI handlers; they do not communicate with the relay and are not required in apps under test. In CI, wait for the photo review and camera readiness through your test runner before sending the next action.

The fixtures are generated locally. `colors.mp4` cycles through red, green, and blue at 320×240 and 15 fps. `checkerboard.png` is a 480×640 portrait image. `moving-shapes.mp4` has a moving red circle and green square at 1280×720 and 24 fps. Both videos loop every three seconds. This session keeps the first video's 320×240, 15 fps camera format, fits the other fixtures without cropping, and preserves their playback speed.

For Android, start the AVD with `camrelay emulator start --platform android --avd <name>`, omit `--paused` and `--wait-for-frame`, add `--platform android --avd <name>` to the `run` command, and use the same `select`, `replay`, `next`, and `previous` commands. The emulator applies source orientation metadata and loops video at its source cadence. Stop the AVD separately with `camrelay emulator stop --platform android --avd <name>`.

## Repeatable Android validation

From the repository root, choose any stopped AVD:

```sh
./scripts/generate-fixtures.sh
swift build
cd Examples/CamRelayExpo
npm run android:validation-build
cd ../..
AVD_NAME=your_avd_name
./scripts/validate-android.sh "$AVD_NAME"
```

The script starts and stops the AVD with separate lifecycle commands, installs the release example, and checks front/back discovery, preview, photo capture, fixture switching, static and rotated orientation patterns, three-color video cadence and looping, app-process continuity after relay shutdown, failed-selection preservation, unchanged `environment.ini`, and explicit emulator shutdown. It requires `adb`, `jq`, ImageMagick, `rg`, and `xmllint`; artifacts stay under `.build/validation`.

Start validation with `npm run typecheck` and `npm test` from `Examples/CamRelayExpo`. The tests cover capture progress, review navigation, repeated captures, file URLs, duplicate actions, and failure recovery without a native camera. Preview or native changes also require the relevant virtual-device scenario.
