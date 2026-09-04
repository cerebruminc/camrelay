# CamRelay Expo example

This example is a small Expo development build that renders a `react-native-vision-camera` preview. It provides a faster compatibility check for React Native camera apps without depending on another application.

It cannot run in Expo Go because VisionCamera contains native iOS code. The first run generates and builds a local iOS project; later JavaScript-only changes can use the existing build.

## Install

```sh
cd Examples/CamRelayExpo
npm install
```

The install applies `patches/react-native-vision-camera+4.7.3.patch`. VisionCamera normally rejects every iOS Simulator at compile time. The patch keeps that rejection when no video device exists, permits configuration when CamRelay exposes a discoverable synthetic camera, and avoids configuring the unused audio session because this example disables audio.

## First build

Boot one iOS Simulator, then run:

```sh
npm run ios
```

This generates the disposable `ios` directory, builds the native development app, installs it, and starts Metro. The generated native directory is ignored by Git.

## Verify CamRelay video

Build CamRelay's injected runtime from the repository root:

```sh
./scripts/build-runtime.sh
```

Start CamRelay with a video fixture:

```sh
swift run camrelay /absolute/path/to/fixture.mp4
```

Relaunch **CamRelay Expo** after the relay starts. The example must show:

- The selected synthetic camera name.
- `Camera: active`.
- `Preview: active`.
- Visible motion as the video fixture advances and loops.

Use the on-screen button to exercise both front and back synthetic cameras. If CamRelay is not active when the app launches, the example instead explains that no camera was discovered.

For later runs, keep the installed native app and start Metro with:

```sh
npm start
```
