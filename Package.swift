// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "Yapp", platforms: [.macOS(.v14)], dependencies: [.package(path: "Vendor/WhisperKit")], targets: [.executableTarget(name: "Yapp", dependencies: [.product(name: "WhisperKit", package: "WhisperKit")]), .testTarget(name: "YappTests", dependencies: ["Yapp"])])
