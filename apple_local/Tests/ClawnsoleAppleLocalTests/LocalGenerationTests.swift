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
    XCTAssertTrue(prompt.contains("Frame 3/5"))
    XCTAssertTrue(prompt.contains("1.00s"))
    XCTAssertTrue(prompt.contains("50%"))
    XCTAssertTrue(prompt.contains("Preserve every locked detail"))
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
    XCTAssertLessThanOrEqual(locked.count, 320)
    XCTAssertLessThanOrEqual(frame.count, 480)
  }

  func testAnimationAttemptsDropRejectedReferenceBeforeFailing() {
    let attempts = AnimationPromptPlan.attempts(
      lockedPrompt: "Locked fox design.",
      originalPrompt: "A fox waves",
      frameIndex: 1,
      frameCount: 6,
      frameRate: 6,
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
      frameIndex: 0,
      frameCount: 6,
      frameRate: 6,
      hasReference: false
    )

    XCTAssertEqual(attempts.count, 3)
    XCTAssertTrue(attempts.allSatisfy { !$0.includeReference })
    XCTAssertEqual(attempts.map(\.useFallbackStyle), [false, false, true])
    XCTAssertEqual(attempts[2].prompt, "A fox waves slowly")
  }

  func testAnimationCanHoldACompletedFrameAfterAppleRejectsALaterFrame() throws {
    let image = CGContext(
      data: nil,
      width: 2,
      height: 2,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!
    let error = LocalGenerationError.imageCreationFailed(
      frame: 6,
      frameCount: 6,
      attempts: 3,
      retriedWithoutReference: true,
      reason: "Unsupported language"
    )

    XCTAssertThrowsError(
      try AnimationFrameRecovery.recoveredFrame(
        after: error,
        frameIndex: 0,
        lastSuccessfulFrame: nil
      )
    )
    let recovered = try AnimationFrameRecovery.recoveredFrame(
      after: error,
      frameIndex: 5,
      lastSuccessfulFrame: image
    )
    XCTAssertEqual(recovered.width, image.width)
    XCTAssertEqual(recovered.height, image.height)
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
