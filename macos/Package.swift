// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "DshNotch",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "dsh-notch", targets: ["DshNotch"]),
  ],
  targets: [
    .executableTarget(
      name: "DshNotch",
      path: "Sources"
    ),
  ]
)
