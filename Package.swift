// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleScanner",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SimpleScannerCore", targets: ["SimpleScannerCore"]),
        .executable(name: "SimpleScanner", targets: ["SimpleScanner"]),
    ],
    targets: [
        .target(name: "SimpleScannerCore", resources: [.copy("Resources/vendors.json")]),
        .executableTarget(name: "SimpleScanner", dependencies: ["SimpleScannerCore"]),
        .testTarget(name: "SimpleScannerCoreTests", dependencies: ["SimpleScannerCore"]),
        .testTarget(name: "SimpleScannerAppTests", dependencies: ["SimpleScanner", "SimpleScannerCore"]),
    ],
    swiftLanguageModes: [.v5]
)
