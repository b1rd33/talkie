// swift-tools-version: 5.10

import PackageDescription

// Dependabot dependency mirror only. The app remains defined by project.yml;
// keep these exact package URLs and versions synchronized with XcodeGen.
let package = Package(
    name: "TalkieDependencyMirror",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", exact: "0.2.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.15.5"),
    ]
)
