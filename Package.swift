// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dynamite",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dynamite", targets: ["Dynamite"]),
        .library(name: "MacAppUpdates", targets: ["MacAppUpdates"])
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "IslandCore"),
        .target(name: "MacAppUpdates", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "Dynamite", dependencies: ["IslandCore", "MacAppUpdates"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"])
    ]
)
