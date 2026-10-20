// swift-tools-version:5.9
import Foundation
import PackageDescription

// CORE_ONLY=1 leaves out the app, so `swift test` works with just the Command Line Tools
// (the app's SwiftUI macros need an SDK whose Testing macros are missing there).
let coreOnly = ProcessInfo.processInfo.environment["CORE_ONLY"] == "1"

let app: [Target] = coreOnly ? [] : [
    .executableTarget(
        name: "Petal",
        dependencies: ["FileAppCore", .product(name: "Sparkle", package: "Sparkle")],
        linkerSettings: [
            // Sparkle.framework is embedded in Petal.app/Contents/Frameworks by scripts/build-app.sh.
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
        ]),
]

let package = Package(
    name: "Petal",
    platforms: [.macOS(.v14)],
    products: coreOnly ? [] : [
        .executable(name: "Petal", targets: ["Petal"]),
    ],
    dependencies: coreOnly ? [] : [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        .target(name: "FileAppCore"),
        .testTarget(name: "FileAppCoreTests", dependencies: ["FileAppCore"]),
    ] + app
)
