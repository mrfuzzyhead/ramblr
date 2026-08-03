// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Dictator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Dictator", targets: ["Dictator"])
    ],
    targets: [
        .executableTarget(
            name: "Dictator",
            path: "Sources/Dictator"
        )
    ]
)
