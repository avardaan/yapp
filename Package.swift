// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "yapp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "Vendor/WhisperKit"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "yapp",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "YappTests", dependencies: ["yapp"]),
    ]
)
