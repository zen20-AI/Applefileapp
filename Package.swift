// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Petal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Petal", targets: ["Petal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        .target(name: "FileAppCore"),
        .executableTarget(
            name: "Petal",
            dependencies: ["FileAppCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                // Sparkle.framework is embedded in Petal.app/Contents/Frameworks by scripts/build-app.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]),
        .testTarget(name: "FileAppCoreTests", dependencies: ["FileAppCore"]),
    ]
)
