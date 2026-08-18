import ClawnsoleAppleLocal
import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  func testAppleLocalAnimationOnPhysicalDevice() async throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Apple Image Playground is unavailable in the iOS simulator.")
    #else
      guard await LocalGenerationEngine.isAvailable() else {
        XCTFail("Apple Image Playground is unavailable on this physical test device.")
        return
      }

      let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clawnsole-physical-animation-test", isDirectory: true)
      if FileManager.default.fileExists(atPath: outputDirectory.path) {
        try FileManager.default.removeItem(at: outputDirectory)
      }
      defer { try? FileManager.default.removeItem(at: outputDirectory) }
      let request = LocalGenerationRequest(
        requestId: "physical-animation-test",
        mode: .animation,
        prompt:
          "A tiny orange fox in a blue scarf waves one paw, clean hand-drawn cartoon, static camera.",
        aspectRatio: "9:16",
        resolution: "hd",
        durationSeconds: 1,
        frameRate: 6,
        outputDirectory: outputDirectory.path,
        modelsDirectory: outputDirectory.appendingPathComponent("models").path
      )

      let result = try await LocalGenerationEngine().generate(request) { update in
        print("Apple Local physical test: \(update.progress)% \(update.message)")
      }
      XCTAssertEqual(result.pathExtension, "mp4")
      XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
      XCTAssertGreaterThan(
        try FileManager.default.attributesOfItem(atPath: result.path)[.size] as? Int ?? 0,
        0
      )
    #endif
  }

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}
