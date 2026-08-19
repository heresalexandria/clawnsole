import ClawnsoleAppleLocal
import Flutter
import UIKit
import XCTest

private final class LocalProgressRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var messages = [String]()

  func append(_ message: String) {
    lock.lock()
    messages.append(message)
    lock.unlock()
  }

  func snapshot() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return messages
  }
}

class RunnerTests: XCTestCase {
  func testAppleLocalIsUnavailableInSimulator() async {
    #if targetEnvironment(simulator)
      let isAvailable = await LocalGenerationEngine.isAvailable()
      XCTAssertFalse(
        isAvailable,
        "Image Playground must not be advertised when the simulator has no local model."
      )
    #else
      throw XCTSkip("This availability assertion applies only to iOS Simulator.")
    #endif
  }

  func testAppleLocalImageOnPhysicalDevice() async throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Apple Image Playground is unavailable in the iOS simulator.")
    #else
      guard await LocalGenerationEngine.isAvailable() else {
        XCTFail("Apple Image Playground is unavailable on this physical test device.")
        return
      }

      let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clawnsole-physical-image-test", isDirectory: true)
      if FileManager.default.fileExists(atPath: outputDirectory.path) {
        try FileManager.default.removeItem(at: outputDirectory)
      }
      defer { try? FileManager.default.removeItem(at: outputDirectory) }
      let request = LocalGenerationRequest(
        requestId: "physical-image-test",
        mode: .image,
        prompt: "A tiny orange fox in a blue scarf, clean hand-drawn illustration.",
        aspectRatio: "9:16",
        resolution: "hd",
        durationSeconds: 1,
        frameRate: 1,
        outputDirectory: outputDirectory.path,
        modelsDirectory: outputDirectory.appendingPathComponent("models").path
      )

      let recorder = LocalProgressRecorder()
      let result = try await LocalGenerationEngine().generate(request) { update in
        recorder.append(update.message)
        print("Apple Local physical test: \(update.progress)% \(update.message)")
      }
      XCTAssertEqual(result.pathExtension, "png")
      XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
      XCTAssertGreaterThan(
        try FileManager.default.attributesOfItem(atPath: result.path)[.size] as? Int ?? 0,
        0
      )
      if let image = UIImage(contentsOfFile: result.path) {
        let attachment = XCTAttachment(image: image, quality: .original)
        attachment.name = "Apple Local image"
        attachment.lifetime = .keepAlways
        add(attachment)
      } else {
        XCTFail("Apple Local returned an unreadable PNG.")
      }
      let messages = recorder.snapshot()
      XCTAssertTrue(
        messages.contains { $0.contains("Generating local image") },
        "The physical test must exercise still-image generation."
      )
    #endif
  }

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}
