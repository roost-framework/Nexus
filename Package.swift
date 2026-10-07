// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-nexus",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "Nexus", targets: ["Nexus"]),
        .library(name: "NexusRouter", targets: ["NexusRouter"]),
        .library(name: "NexusHummingbird", targets: ["NexusHummingbird"]),
        .library(name: "NexusVapor", targets: ["NexusVapor"]),
        .library(name: "NexusTest", targets: ["NexusTest"]),
    ],
    traits: [
        // Disable default traits (`traits: []`) to skip fetching Vapor when you only use the Hummingbird adapter.
        .trait(name: "Vapor", description: "The NexusVapor adapter and its Vapor dependency."),
        .default(enabledTraits: ["Vapor"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-http-types.git",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird-websocket.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/vapor/vapor.git",
            from: "4.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            from: "3.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-metrics.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio.git",
            from: "2.77.0"
        ),
        .package(
            url: "https://github.com/typelift/SwiftCheck.git",
            from: "0.12.0"
        ),
    ],
    targets: [
        .systemLibrary(
            name: "CNexusZlib",
            providers: [.apt(["zlib1g-dev"]), .brew(["zlib"])]
        ),
        // MARK: Core

        .target(
            name: "Nexus",
            dependencies: [
                "CNexusZlib",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
                .product(name: "Metrics", package: "swift-metrics"),
            ]
        ),

        // MARK: Router DSL

        .target(
            name: "NexusRouter",
            dependencies: [
                "Nexus",
            ]
        ),

        // MARK: Hummingbird Adapter

        .target(
            name: "NexusHummingbird",
            dependencies: [
                "Nexus",
                "NexusRouter",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),

        // MARK: Vapor Adapter

        .target(
            name: "NexusVapor",
            dependencies: [
                "Nexus",
                "NexusRouter",
                .product(name: "Vapor", package: "vapor", condition: .when(traits: ["Vapor"])),
            ]
        ),

        // MARK: Test Helpers

        .target(
            name: "NexusTest",
            dependencies: [
                "Nexus",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "SwiftCheck", package: "SwiftCheck"),
            ]
        ),

        // MARK: Tests

        .testTarget(
            name: "NexusTests",
            dependencies: [
                "CNexusZlib",
                "Nexus",
                "NexusTest",
                "NexusHummingbird",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "SwiftCheck", package: "SwiftCheck"),
            ],
            exclude: ["COVERAGE_IMPROVEMENTS.md"]
        ),
        .testTarget(
            name: "NexusRouterTests",
            dependencies: [
                "Nexus",
                "NexusRouter",
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
        .testTarget(
            name: "NexusHummingbirdTests",
            dependencies: [
                "Nexus",
                "NexusRouter",
                "NexusHummingbird",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
        .testTarget(
            name: "NexusVaporTests",
            dependencies: [
                "Nexus",
                "NexusRouter",
                "NexusHummingbird",
                "NexusVapor",
                .product(name: "Vapor", package: "vapor", condition: .when(traits: ["Vapor"])),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            exclude: ["README.md", "INTEGRATION_TEST_SUMMARY.md"]
        ),
        // MARK: Streaming Transport Tests
        .testTarget(
            name: "NexusStreamingTests",
            dependencies: [
                "Nexus",
                "NexusHummingbird",
                "NexusVapor",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "Vapor", package: "vapor", condition: .when(traits: ["Vapor"])),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ]
        ),
        // Temporarily disabled benchmarks due to API updates
        // .testTarget(
        //     name: "NexusVaporBenchmarks",
        //     dependencies: [
        //         "Nexus",
        //         "NexusRouter",
        //         "NexusVapor",
        //         .product(name: "Vapor", package: "vapor", condition: .when(traits: ["Vapor"])),
        //         .product(name: "HTTPTypes", package: "swift-http-types"),
        //     ]
        // ),
    ]
)
