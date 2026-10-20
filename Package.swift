// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Amiga-View",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Amiga-View", targets: ["AmigaView"])],
    targets: [
        .target(name: "AmigaViewCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "AmigaView", dependencies: ["AmigaViewCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AmigaViewCoreTests", dependencies: ["AmigaViewCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
