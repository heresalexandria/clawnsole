// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "ClawnsoleAppleLocal",
  platforms: [
    .iOS(.v15),
    .macOS(.v13),
  ],
  products: [
    .library(name: "ClawnsoleAppleLocal", targets: ["ClawnsoleAppleLocal"]),
    .executable(
      name: "clawnsole-apple-generator",
      targets: ["ClawnsoleAppleGenerator"]
    ),
  ],
  dependencies: [],
  targets: [
    .target(name: "ClawnsoleAppleLocal"),
    .executableTarget(
      name: "ClawnsoleAppleGenerator",
      dependencies: ["ClawnsoleAppleLocal"]
    ),
    .testTarget(
      name: "ClawnsoleAppleLocalTests",
      dependencies: ["ClawnsoleAppleLocal"]
    ),
  ]
)
