// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LorcasterPlayer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LorcasterPlayer", targets: ["LorcasterPlayer"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "LorcasterPlayer",
            dependencies: [
                .product(name: "LorcasterCore", package: "Core")
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ],
    swiftLanguageModes: [.v6]
)
