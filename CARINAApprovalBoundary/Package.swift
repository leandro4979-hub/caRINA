// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Carina",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CarinaCore", targets: ["Carina"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .brew(["sqlite3"]),
                .apt(["libsqlite3-dev"])
            ]
        ),
        .target(name: "Carina", dependencies: ["CSQLite"]),
        .testTarget(name: "CarinaTests", dependencies: ["Carina"])
    ]
)
