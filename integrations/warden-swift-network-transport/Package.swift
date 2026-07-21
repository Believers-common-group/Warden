// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WardenSwiftTransport",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9)],
    products: [
        .library(name: "WardenSwiftTransport", targets: ["WardenSwiftTransport"]),
        .executable(name: "warden-reference-client", targets: ["WardenReferenceClient"])
    ],
    targets: [
        .target(name: "WardenSwiftTransport"),
        .executableTarget(name: "WardenReferenceClient", dependencies: ["WardenSwiftTransport"]),
        .testTarget(name: "WardenSwiftTransportTests", dependencies: ["WardenSwiftTransport"])
    ]
)
