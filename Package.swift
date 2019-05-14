// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "homekit-webos-picture-mode",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/ahti/HAP.git", .branch("nio2")),
        .package(url: "https://github.com/ahti/nio-websocket-client.git", .branch("master")),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "homekit-webos-picture-mode",
            dependencies: ["HAP", "NIOWebSocketClient", "SwiftyJSON"]),
        .testTarget(
            name: "homekit-webos-picture-modeTests",
            dependencies: ["homekit-webos-picture-mode"]),
    ]
)
