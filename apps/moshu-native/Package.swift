// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MoshuNative",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Moshu", targets: ["Moshu"])],
    targets: [
        .target(name: "MoshuCore", resources: [.copy("Resources")]),
        .executableTarget(name: "Moshu", dependencies: ["MoshuCore"]),
        .testTarget(name: "MoshuCoreTests", dependencies: ["MoshuCore", "Moshu"])
    ]
)
