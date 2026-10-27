// swift-tools-version:6.0
import Foundation
import PackageDescription

let librashaderDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("build/librashader").path

let package = Package(
    name: "Amiga-View",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Amiga-View", targets: ["AmigaView"])],
    targets: [
        // Objective-C bridge to librashader (build/librashader, made by scripts/librashader.sh).
        // The rpath lets tests and `swift run` find the dylib; bundle.sh adds Frameworks.
        .target(name: "LibrashaderBridge",
                cSettings: [.unsafeFlags(["-I\(librashaderDir)"])],
                linkerSettings: [.unsafeFlags(["-L\(librashaderDir)", "-lrashader",
                                               "-Xlinker", "-rpath", "-Xlinker", librashaderDir])]),
        .target(name: "AmigaViewCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "AmigaView", dependencies: ["AmigaViewCore", "LibrashaderBridge"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AmigaViewCoreTests", dependencies: ["AmigaViewCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AmigaViewTests", dependencies: ["AmigaView", "LibrashaderBridge"], exclude: ["Fixtures"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
