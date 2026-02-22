// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "AgentSim",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
  ],
  targets: [
    // Library: all logic, testable
    .target(
      name: "AgentSimLib",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "FBControlCore",
        "FBSimulatorControl",
        "FBDeviceControl",
        "XCTestBootstrap",
      ],
      path: "Sources/AgentSim",
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
        ])
      ]
    ),
    // Executable: thin entry point
    .executableTarget(
      name: "AgentSim",
      dependencies: ["AgentSimLib"],
      path: "Sources/AgentSimCLI",
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-dead_strip",
          "-Xlinker", "-headerpad_max_install_names",
          "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
        ])
      ]
    ),
    // Tests
    .testTarget(
      name: "AgentSimTests",
      dependencies: ["AgentSimLib"],
      path: "Tests/AgentSimTests"
    ),
    .binaryTarget(
      name: "FBControlCore",
      path: "Frameworks/FBControlCore.xcframework"
    ),
    .binaryTarget(
      name: "FBSimulatorControl",
      path: "Frameworks/FBSimulatorControl.xcframework"
    ),
    .binaryTarget(
      name: "FBDeviceControl",
      path: "Frameworks/FBDeviceControl.xcframework"
    ),
    .binaryTarget(
      name: "XCTestBootstrap",
      path: "Frameworks/XCTestBootstrap.xcframework"
    ),
  ]
)
