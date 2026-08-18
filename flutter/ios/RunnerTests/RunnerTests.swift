import AVFoundation
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

      let recorder = LocalProgressRecorder()
      let result = try await LocalGenerationEngine().generate(request) { update in
        recorder.append(update.message)
        print("Apple Local physical test: \(update.progress)% \(update.message)")
      }
      XCTAssertEqual(result.pathExtension, "mp4")
      XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
      XCTAssertGreaterThan(
        try FileManager.default.attributesOfItem(atPath: result.path)[.size] as? Int ?? 0,
        0
      )
      let asset = AVURLAsset(url: result)
      let imageGenerator = AVAssetImageGenerator(asset: asset)
      imageGenerator.appliesPreferredTrackTransform = true
      let duration = CMTimeGetSeconds(asset.duration)
      let sampleTimes = [0.0, duration * 0.5, max(0, duration - (1.0 / 6.0))]
      for (index, seconds) in sampleTimes.enumerated() {
        let frame = try imageGenerator.copyCGImage(
          at: CMTime(seconds: seconds, preferredTimescale: 600),
          actualTime: nil
        )
        let attachment = XCTAttachment(
          image: UIImage(cgImage: frame),
          quality: .original
        )
        attachment.name = "Apple Local animation sample \(index + 1)"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
      let messages = recorder.snapshot()
      XCTAssertTrue(
        messages.contains { $0.contains("Generating continuity anchor") },
        "The physical test must generate individual full-size continuity anchors."
      )
      XCTAssertTrue(
        messages.contains { $0.contains("Completing referenced frame") },
        "The physical test must exercise the composite-reference frame path."
      )
      XCTAssertFalse(
        messages.contains { $0.contains("failed continuity validation") },
        "Every generated physical-device frame should pass continuity validation."
      )
    #endif
  }

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}
