// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NixflixSupervisor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NixflixSupervisor", targets: ["NixflixSupervisor"])
    ],
    targets: [
        .executableTarget(name: "NixflixSupervisor"),
    ]
)
