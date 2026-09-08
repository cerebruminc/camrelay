// swift-tools-version: 6.2

import PackageDescription

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
            dependencies: ["CamRelayCore"]
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
            dependencies: ["CamRelayIOS"]
        ),
        .testTarget(
            name: "CamRelayAndroidTests",
            dependencies: ["CamRelayAndroid", "CamRelayCore"]
        ),
    ]
)
