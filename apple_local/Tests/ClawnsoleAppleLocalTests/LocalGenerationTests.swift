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

  func testMasterPromptRequestsOneStableComposition() {
    let prompt = AnimationPromptPlan.masterFramePrompt(
      lockedPrompt: "Locked hero model sheet."
    )
    XCTAssertTrue(prompt.contains("one cohesive master frame"))
    XCTAssertTrue(prompt.contains("center 80%"))
    XCTAssertTrue(prompt.contains("one stable background"))
    XCTAssertTrue(prompt.contains("No storyboard"))
  }

  func testExpandedLockRejectsAStoryboardAndAcceptsOneCompactSentence() {
    XCTAssertNil(
      AnimationPromptPlan.validatedExpandedLock(
        """
        1. **Sloth on skateboard**
        2. **Sloth skateboarding in another scene**
        """
      )
    )
    XCTAssertEqual(
      AnimationPromptPlan.validatedExpandedLock(
        "A friendly brown sloth in a blue shirt rides one red skateboard through a sunny skatepark, with soft cartoon linework and a fixed low camera."
      ),
      "A friendly brown sloth in a blue shirt rides one red skateboard through a sunny skatepark, with soft cartoon linework and a fixed low camera."
    )
  }

  func testFallbackPromptFitsImagePlaygroundConceptBudget() {
    let locked = AnimationPromptPlan.fallbackLock(
      for: String(repeating: "A very detailed cartoon direction. ", count: 80)
    )
    let frame = AnimationPromptPlan.masterFramePrompt(lockedPrompt: locked)
    XCTAssertLessThanOrEqual(locked.count, 320)
    XCTAssertLessThanOrEqual(frame.count, 480)
  }

  func testAnimationAttemptsDropRejectedReferenceBeforeFailing() {
    let attempts = AnimationPromptPlan.attempts(
      lockedPrompt: "Locked fox design.",
      originalPrompt: "A fox waves",
      hasReference: true
    )

    XCTAssertEqual(attempts.count, 3)
    XCTAssertEqual(attempts.map(\.includeReference), [true, true, false])
    XCTAssertEqual(attempts.map(\.useFallbackStyle), [false, false, true])
    XCTAssertEqual(attempts[2].prompt, "A fox waves")
    XCTAssertFalse(attempts[2].prompt.contains("Locked"))
    XCTAssertLessThanOrEqual(attempts[0].prompt.count, 480)
    XCTAssertLessThanOrEqual(attempts[1].prompt.count, 300)
  }

  func testAnimationAttemptsRetryFirstFrameWithoutReference() {
    let attempts = AnimationPromptPlan.attempts(
      lockedPrompt: "Locked fox design.",
      originalPrompt: "  A fox\n  waves   slowly  ",
      hasReference: false
    )

    XCTAssertEqual(attempts.count, 3)
    XCTAssertTrue(attempts.allSatisfy { !$0.includeReference })
    XCTAssertEqual(attempts.map(\.useFallbackStyle), [false, false, true])
    XCTAssertEqual(attempts[2].prompt, "A fox waves slowly")
  }

  func testAnimationFailureNamesFrameAndRecovery() {
    let error = LocalGenerationError.imageCreationFailed(
      frame: 2,
      frameCount: 6,
      attempts: 3,
      retriedWithoutReference: true,
      reason: "Apple still reported an image-creation failure."
    )

    XCTAssertEqual(error.failureProgress, 5 + (1.0 / 6.0) * 88)
    XCTAssertTrue(error.localizedDescription.contains("frame 2 of 6"))
    XCTAssertTrue(error.localizedDescription.contains("without the reference frame"))
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
