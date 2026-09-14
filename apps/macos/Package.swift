// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Taskly",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Taskly",
            path: "Sources/Taskly",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "TasklyTests",
            dependencies: ["Taskly"],
            path: "Tests/TasklyTests"
        )
    ]
)
