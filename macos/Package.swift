// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalWorkspace",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LocalWorkspace", targets: ["LocalWorkspace"])],
    targets: [.executableTarget(name: "LocalWorkspace")]
)
