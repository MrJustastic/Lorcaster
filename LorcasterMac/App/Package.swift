// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lorcaster",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Lorcaster", targets: ["Lorcaster"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Server"),
        .package(path: "../Player")
    ],
    targets: [
        .executableTarget(
            name: "Lorcaster",
            dependencies: [
                .product(name: "LorcasterCore", package: "Core"),
                .product(name: "LorcasterServer", package: "Server"),
                .product(name: "LorcasterPlayer", package: "Player")
            ],
            path: "Sources/Lorcaster",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")],
            linkerSettings: [.linkedFramework("MediaPlayer")]
        )
    ],
    swiftLanguageModes: [.v6]
)
