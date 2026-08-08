// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Carina",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Carina", targets: ["Carina"])
    ],
    targets: [
        .target(name: "Carina"),
        .testTarget(name: "CarinaTests", dependencies: ["Carina"])
    ]
)
