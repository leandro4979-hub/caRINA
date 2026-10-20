// swift-tools-version: 5.9

import PackageDescription

#if os(macOS)
// Use SDK SQLite; Homebrew's dylib has a different signing identity from the app.
let sqlitePkgConfig: String? = nil
#else
let sqlitePkgConfig: String? = "sqlite3"
#endif

let package = Package(
    name: "Carina",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CarinaCore", targets: ["Carina"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: sqlitePkgConfig,
            providers: [
                .apt(["libsqlite3-dev"])
            ]
        ),
        .target(name: "Carina", dependencies: ["CSQLite"]),
        .testTarget(name: "CarinaTests", dependencies: ["Carina"])
    ]
)
