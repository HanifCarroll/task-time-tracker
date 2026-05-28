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
    targets: [
        .executableTarget(
            name: "TaskTimeTracker",
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
