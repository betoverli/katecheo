// swift-tools-version: 5.9
import PackageDescription

// Phase 5: Capacitor is no longer linked into the App target.
// This local package is kept as an empty stub so leftover paths do not break
// tooling; the Xcode project does not depend on CapApp-SPM anymore.
let package = Package(
    name: "CapApp-SPM",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapApp-SPM",
            targets: ["CapApp-SPM"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CapApp-SPM",
            dependencies: [])
    ]
)
