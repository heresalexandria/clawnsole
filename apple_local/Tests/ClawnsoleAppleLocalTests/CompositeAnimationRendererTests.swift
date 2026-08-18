import XCTest

@testable import ClawnsoleAppleLocal

final class CompositeAnimationRendererTests: XCTestCase {
  func testSheetLayoutUsesCellsThatMatchOutputOrientation() {
    XCTAssertEqual(
      AnimationSheetLayout.forDimensions(width: 320, height: 512),
      AnimationSheetLayout(columns: 6, rows: 4)
    )
    XCTAssertEqual(
      AnimationSheetLayout.forDimensions(width: 512, height: 320),
      AnimationSheetLayout(columns: 4, rows: 6)
    )
    XCTAssertEqual(
      AnimationSheetLayout.forDimensions(width: 512, height: 512),
      AnimationSheetLayout(columns: 5, rows: 5)
    )
  }

  func testTimelineUsesExactAndIntermediateAtlasFrames() {
    let first = AnimationTimelineSample.at(
      frameIndex: 0,
      frameCount: 6,
      keyframeCount: 24
    )
    let middle = AnimationTimelineSample.at(
      frameIndex: 1,
      frameCount: 6,
      keyframeCount: 24
    )
    let last = AnimationTimelineSample.at(
      frameIndex: 5,
      frameCount: 6,
      keyframeCount: 24
    )

    XCTAssertEqual(first, .init(beforeIndex: 0, afterIndex: 0, fraction: 0))
    XCTAssertEqual(middle.beforeIndex, 4)
    XCTAssertEqual(middle.afterIndex, 5)
    XCTAssertEqual(middle.fraction, 0.6, accuracy: 0.000_001)
    XCTAssertEqual(last, .init(beforeIndex: 23, afterIndex: 23, fraction: 0))
  }

  func testAtlasCropsExactlyTwentyFourKeyframes() throws {
    let layout = AnimationSheetLayout(columns: 6, rows: 4)
    let sheet = solidImage(width: 600, height: 400)
    let keyframes = try layout.keyframes(from: sheet)

    XCTAssertEqual(keyframes.count, 24)
    XCTAssertTrue(keyframes.allSatisfy { $0.width == 100 && $0.height == 100 })
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
  }

  func testConsistencyGateAcceptsAUniformTwentyFourFrameAtlas() {
    let frames = (0..<24).map { _ in solidImage(width: 32, height: 48) }
    XCTAssertTrue(AnimationFrameConsistency.acceptsAtlas(frames))
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
