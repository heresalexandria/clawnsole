import XCTest

@testable import ClawnsoleAppleLocal

final class CompositeAnimationRendererTests: XCTestCase {
  func testAnchorPlanKeepsAtMostFourOutputFramesBetweenAnchors() {
    XCTAssertEqual(AnimationAnchorPlan.anchorCount(forFrameCount: 1), 1)
    XCTAssertEqual(AnimationAnchorPlan.anchorCount(forFrameCount: 6), 3)
    XCTAssertEqual(AnimationAnchorPlan.anchorCount(forFrameCount: 18), 6)
    XCTAssertEqual(AnimationAnchorPlan.anchorCount(forFrameCount: 48), 13)
  }

  func testTimelineUsesExactAndIntermediateAnchorFrames() {
    let first = AnimationTimelineSample.at(
      frameIndex: 0,
      frameCount: 6,
      keyframeCount: 3
    )
    let middle = AnimationTimelineSample.at(
      frameIndex: 1,
      frameCount: 6,
      keyframeCount: 3
    )
    let last = AnimationTimelineSample.at(
      frameIndex: 5,
      frameCount: 6,
      keyframeCount: 3
    )

    XCTAssertEqual(first, .init(beforeIndex: 0, afterIndex: 0, fraction: 0))
    XCTAssertEqual(middle.beforeIndex, 0)
    XCTAssertEqual(middle.afterIndex, 1)
    XCTAssertEqual(middle.fraction, 0.4, accuracy: 0.000_001)
    XCTAssertEqual(last, .init(beforeIndex: 2, afterIndex: 2, fraction: 0))
  }

  func testContinuityBoardAndTargetCropHavePredictableGeometry() throws {
    let frame = solidImage(width: 32, height: 48)
    let board = try CompositeAnimationRenderer.continuityBoard(
      before: frame,
      after: frame,
      previous: frame
    )
    let target = try CompositeAnimationRenderer.targetCell(from: board)

    XCTAssertEqual(board.width, 1024)
    XCTAssertEqual(board.height, 1024)
    XCTAssertEqual(target.width, 472)
    XCTAssertEqual(target.height, 472)
    let targetColor = centerColor(of: target)
    XCTAssertEqual(targetColor.red, 0.82, accuracy: 0.03)
    XCTAssertEqual(targetColor.green, 0.82, accuracy: 0.03)
    XCTAssertEqual(targetColor.blue, 0.82, accuracy: 0.03)
    XCTAssertTrue(AnimationFrameConsistency.looksLikeContinuityBoard(board))
    XCTAssertFalse(AnimationFrameConsistency.looksLikeContinuityBoard(frame))
  }

  func testCompositePromptsExplainTheSingleReferenceLayout() {
    let prompt = CompositeAnimationPromptPlan.targetOnlyPrompt(
      originalPrompt: "a fox waves",
      fraction: 0.5
    )
    XCTAssertTrue(prompt.contains("2 by 2 continuity board"))
    XCTAssertTrue(prompt.contains("previous frame bottom left"))
    XCTAssertTrue(prompt.contains("blank target bottom right"))
    XCTAssertLessThanOrEqual(prompt.count, 360)

    let anchorPrompt = CompositeAnimationPromptPlan.anchorOnlyPrompt(
      lockedPrompt: "same fox and setting",
      originalPrompt: "the fox waves",
      fraction: 0.5
    )
    XCTAssertTrue(anchorPrompt.contains("immutable design master"))
    XCTAssertTrue(anchorPrompt.contains("previous anchor twice"))
    XCTAssertTrue(anchorPrompt.contains("50%"))
    XCTAssertLessThanOrEqual(anchorPrompt.count, 430)
  }

  private func solidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  private func centerColor(of image: CGImage) -> (red: Double, green: Double, blue: Double) {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &pixel,
      width: 1,
      height: 1,
      bitsPerComponent: 8,
      bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return (
      red: Double(pixel[0]) / 255,
      green: Double(pixel[1]) / 255,
      blue: Double(pixel[2]) / 255
    )
  }
}
