// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LorcasterServer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LorcasterServer", targets: ["LorcasterServer"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "LorcasterServer",
            dependencies: [
                .product(name: "LorcasterCore", package: "Core")
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ],
    swiftLanguageModes: [.v6]
)
