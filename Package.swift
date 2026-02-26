// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IGTranscriber",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "IGTranscriber",
            targets: ["IGTranscriber"]
        )
    ],
    targets: [
        .executableTarget(
            name: "IGTranscriber",
            path: "Sources"
        )
    ]
)
