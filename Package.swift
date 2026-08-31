// swift-tools-version:6.0
import PackageDescription

// AppKit menu bar app, no external dependencies.
// Everything runs on the main thread (the event tap source is attached to the main
// run loop), so Swift 5 language mode is used deliberately in the app target:
// strict concurrency checking would only add noise around non-Sendable CF/CG types.
let package = Package(
    name: "TwoCmd",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "2cmd", targets: ["TwoCmd"])
    ],
    targets: [
        // Pure gesture-recognition logic, kept free of AppKit so it can be checked
        // standalone (see `make test`) without the Accessibility permission.
        .target(name: "TwoCmdCore"),
        .executableTarget(
            name: "TwoCmd",
            dependencies: ["TwoCmdCore"],
            path: "Sources/TwoCmd",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
