// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppleFileApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AppleFileApp", targets: ["AppleFileApp"]),
    ],
    targets: [
        .target(name: "FileAppCore"),
        .executableTarget(name: "AppleFileApp", dependencies: ["FileAppCore"]),
        .testTarget(name: "FileAppCoreTests", dependencies: ["FileAppCore"]),
    ]
)
