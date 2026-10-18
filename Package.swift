// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Maclip",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure model logic (history list, dedupe, pinning, persistence) so it can be unit tested.
        .target(name: "MaclipCore"),
        // The menu bar app itself: pasteboard watcher, global hotkey, floating panel, paste.
        .executableTarget(
            name: "Maclip",
            dependencies: ["MaclipCore"]
        ),
        .testTarget(
            name: "MaclipCoreTests",
            dependencies: ["MaclipCore"]
        ),
    ]
)
