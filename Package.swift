// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "dark-signal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "dark-signal", targets: ["dark-signal"])
    ],
    targets: [
        // The logic lives in a library so that argument parsing and the LaunchAgent
        // it generates can be checked without watching for a real appearance change.
        .target(name: "DarkSignalCore"),
        .executableTarget(name: "dark-signal", dependencies: ["DarkSignalCore"]),
        // Checks are a plain executable rather than an XCTest target on purpose:
        // `swift run dark-signal-tests` works with the Command Line Tools alone,
        // so the suite runs on a machine that has no Xcode installed.
        .executableTarget(name: "dark-signal-tests", dependencies: ["DarkSignalCore"]),
    ]
)
