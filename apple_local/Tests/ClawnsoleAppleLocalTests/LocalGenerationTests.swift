import XCTest

@testable import ClawnsoleAppleLocal

final class LocalGenerationTests: XCTestCase {
  func testAnimationFrameCountUsesDurationAndFrameRate() throws {
    let request = makeRequest(mode: .animation, duration: 4, frameRate: 3)
    try request.validate()
    XCTAssertEqual(request.frameCount, 12)
  }

  func testImageAlwaysUsesOneFrame() throws {
    let request = makeRequest(mode: .image, duration: 8, frameRate: 6)
    try request.validate()
    XCTAssertEqual(request.frameCount, 1)
  }

  func testDimensionsStayDiffusionFriendly() throws {
    let request = makeRequest(aspectRatio: "9:16", resolution: "fhd")
    let dimensions = try request.dimensions()
    XCTAssertEqual(dimensions.width, 448)
    XCTAssertEqual(dimensions.height, 768)
    XCTAssertEqual(dimensions.width % 64, 0)
    XCTAssertEqual(dimensions.height % 64, 0)
  }

  func testFramePromptCarriesContinuityAndProgress() {
    let prompt = AnimationPromptPlan.framePrompt(
      lockedPrompt: "Locked hero model sheet.",
      frameIndex: 2,
      frameCount: 5,
      frameRate: 2
    )
    XCTAssertTrue(prompt.contains("frame 3 of 5"))
    XCTAssertTrue(prompt.contains("1.000 seconds"))
    XCTAssertTrue(prompt.contains("50.0%"))
    XCTAssertTrue(prompt.contains("Preserve every continuity-locked"))
  }

  func testFallbackPromptFitsImagePlaygroundConceptBudget() {
    let locked = AnimationPromptPlan.fallbackLock(
      for: String(repeating: "A very detailed cartoon direction. ", count: 80)
    )
    let frame = AnimationPromptPlan.framePrompt(
      lockedPrompt: locked,
      frameIndex: 0,
      frameCount: 2,
      frameRate: 2
    )
    XCTAssertLessThanOrEqual(locked.count, 600)
    XCTAssertLessThanOrEqual(frame.count, 900)
  }

  private func makeRequest(
    mode: LocalGenerationMode = .animation,
    aspectRatio: String = "16:9",
    resolution: String = "hd",
    duration: Int = 2,
    frameRate: Int = 2
  ) -> LocalGenerationRequest {
    LocalGenerationRequest(
      requestId: "test",
      mode: mode,
      prompt: "A fox waves",
      aspectRatio: aspectRatio,
      resolution: resolution,
      durationSeconds: duration,
      frameRate: frameRate,
      outputDirectory: "/tmp/clawnsole-tests",
      modelsDirectory: "/tmp/clawnsole-models"
    )
  }
}
