// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "terminalmanager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "terminalmanager", targets: ["terminalmanager"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.5"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0")
    ],
    targets: [
        .executableTarget(
            name: "terminalmanager",
            dependencies: [
                "SwiftTerm",
                .product(name: "TOMLKit", package: "TOMLKit")
            ],
            path: "Sources/terminalmanager",
            swiftSettings: [
                .unsafeFlags(
                    ["-cross-module-optimization"],
                    .when(configuration: .release)
                )
            ]
        )
    ]
)
