// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CarinaMacApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../CARINAApprovalBoundary")
    ],
    targets: [
        .executableTarget(
            name: "CarinaMacApp",
            dependencies: [
                .product(name: "CarinaCore", package: "CARINAApprovalBoundary")
            ]
        )
    ]
)
