# CamRelay Expo example

This Expo app validates CamRelay through `react-native-vision-camera` on iOS Simulator and Android Emulator. It uses ordinary camera APIs and has no CamRelay integration or fixture-specific behavior.

The example requires a native development build and does not run in Expo Go.

## Install

```sh
npm install
```

Installation applies the repository's VisionCamera patch. The patch lets VisionCamera use CamRelay's synthetic iOS camera without setting up audio.

## Run on iOS

Build and install the native app:

```sh
npm run ios
```

Start CamRelay from the repository root, then relaunch **CamRelay Expo**. See the [iOS guide](../../docs/ios.md).

## Run on Android

Start the AVD with CamRelay camera support as described in the [Android guide](../../docs/android.md), then build and install the app:

```sh
npm run android
```

## What to verify

With an active relay, the app should show:

- The selected synthetic camera
- An active camera and preview
- An active frame processor with an increasing frame count
- Visible motion for a video fixture

Use the on-screen controls to switch between front and back cameras, capture a photo, and review the saved image. If CamRelay is inactive when the app launches, the app reports that no camera is available.

## Local checks

```sh
npm run typecheck
npm test
```

See [Development](../../docs/development.md) for tests and the Android release build.
