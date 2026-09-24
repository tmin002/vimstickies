// swift-tools-version: 6.2

import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "VimStickies",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "VimStickies",
            dependencies: ["CVimBridge"],
            path: "Sources/VimStickies"
        ),
        .target(
            name: "CVimBridge",
            path: "Sources/CVimBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-L\(packageRoot)/Vendor/LibVim/lib"]),
                .linkedLibrary("vim"),
                .linkedLibrary("ncurses"),
                .linkedLibrary("iconv"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "VimBridgeCheck",
            dependencies: ["CVimBridge"],
            path: "Checks/VimBridgeCheck"
        )
    ]
)
