// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LorcasterCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LorcasterCore", targets: ["LorcasterCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LorcasterCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ],
    swiftLanguageModes: [.v6]
)
