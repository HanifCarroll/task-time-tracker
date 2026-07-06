// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TaskTimeTracker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TaskTimeTracker", targets: ["TaskTimeTracker"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
    ],
    targets: [
        .executableTarget(
            name: "TaskTimeTracker",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/TaskTimeTracker",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TaskTimeTrackerTests",
            dependencies: ["TaskTimeTracker"],
            path: "Tests/TaskTimeTrackerTests"
        )
    ]
)
