// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RestFlow",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RestFlow", targets: ["RestFlow"]),
        .executable(name: "RestFlowChecks", targets: ["RestFlowChecks"]),
        .library(name: "RestFlowCore", targets: ["RestFlowCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-spm.git", exact: "4.6.1"),
    ],
    targets: [
        .target(name: "RestFlowCore"),
        .executableTarget(
            name: "RestFlow",
            dependencies: ["RestFlowCore", .product(name: "Lottie", package: "lottie-spm")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(name: "RestFlowChecks", dependencies: ["RestFlowCore"], path: "Tests/RestFlowChecks"),
    ]
)
