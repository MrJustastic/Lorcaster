// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LorcasterServer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LorcasterServer", targets: ["LorcasterServer"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "LorcasterServer",
            dependencies: [
                .product(name: "LorcasterCore", package: "Core"),
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ],
    swiftLanguageModes: [.v6]
)
