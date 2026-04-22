// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "notcherahud",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "notcherahud",
            targets: ["notcherahud"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "notcherahud"
        ),
    ]
)
