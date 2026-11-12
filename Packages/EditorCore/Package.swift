// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EditorCore",
    products: [
        .library(name: "EditorCore", targets: ["EditorCore"])
    ],
    targets: [
        .target(
            name: "EditorCore",
            path: "Sources/EditorCore"
        ),
        .testTarget(
            name: "EditorCoreTests",
            dependencies: ["EditorCore"],
            path: "Tests/EditorCoreTests"
        )
    ],
    // NOTE: swiftLanguageModes requires swift-tools 6.0; under the
    // specified swift-tools 5.9 the equivalent API is swiftLanguageVersions.
    swiftLanguageVersions: [.v5]
)
