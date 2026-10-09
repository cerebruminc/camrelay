// swift-tools-version: 6.2

import PackageDescription

#if os(Linux)
// Linux uses the shared control socket, without the Simulator implementation.
let iosExcludes = ["FrameServer.swift", "IOSRelay.swift", "MediaFrameSource.swift", "PlaybackEngine.swift", "SimulatorController.swift"]
let iosTestExcludes = ["FrameScheduleTests.swift", "FrameTransportTests.swift", "MediaFrameSourceTests.swift", "PlaybackEngineTests.swift", "SimulatorControllerTests.swift"]
#else
let iosExcludes: [String] = []
let iosTestExcludes: [String] = []
#endif

let package = Package(
    name: "CamRelay",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "camrelay", targets: ["CamRelayCLI"]),
        .library(name: "CamRelayCore", targets: ["CamRelayCore"]),
    ],
    targets: [
        .target(name: "CamRelayCore"),
        .target(
            name: "CamRelayIOS",
            dependencies: ["CamRelayCore"],
            exclude: iosExcludes
        ),
        .target(
            name: "CamRelayAndroid",
            dependencies: ["CamRelayCore"]
        ),
        .executableTarget(
            name: "CamRelayCLI",
            dependencies: ["CamRelayCore", "CamRelayIOS", "CamRelayAndroid"]
        ),
        .testTarget(
            name: "CamRelayCoreTests",
            dependencies: ["CamRelayCore"]
        ),
        .testTarget(
            name: "CamRelayIOSTests",
            dependencies: ["CamRelayIOS"],
            exclude: iosTestExcludes
        ),
        .testTarget(
            name: "CamRelayAndroidTests",
            dependencies: ["CamRelayAndroid", "CamRelayCore"]
        ),
    ]
)
