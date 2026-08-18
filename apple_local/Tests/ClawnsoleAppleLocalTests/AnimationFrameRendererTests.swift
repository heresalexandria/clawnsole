import XCTest

@testable import ClawnsoleAppleLocal

final class AnimationFrameRendererTests: XCTestCase {
  func testMotionPlanSelectsActionAppropriateMovement() {
    XCTAssertEqual(AnimationMotionPlan.forPrompt("sloth skateboarding").style, .tracking)
    XCTAssertEqual(AnimationMotionPlan.forPrompt("a fox waves").style, .bounce)
    XCTAssertEqual(AnimationMotionPlan.forPrompt("a balloon floats").style, .vertical)
    XCTAssertEqual(AnimationMotionPlan.forPrompt("portrait").style, .drift)
  }

  func testTrackingMotionStaysInsideOverscanMargin() {
    let plan = AnimationMotionPlan(style: .tracking)
    for frameIndex in 0..<48 {
      let transform = plan.transform(
        frameIndex: frameIndex,
        frameCount: 48,
        width: 320,
        height: 512
      )
      let horizontalMargin = (transform.scale - 1) * 320 / 2
      let verticalMargin = (transform.scale - 1) * 512 / 2
      XCTAssertLessThanOrEqual(abs(transform.offsetX), horizontalMargin)
      XCTAssertLessThanOrEqual(abs(transform.offsetY), verticalMargin)
    }
  }

  func testRendererKeepsEveryFrameAtTheRequestedDimensions() throws {
    let context = CGContext(
      data: nil,
      width: 32,
      height: 48,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
    let masterFrame = context.makeImage()!
    let motion = AnimationMotionPlan.forPrompt("sloth skateboarding")

    for frameIndex in 0..<6 {
      let frame = try CohesiveAnimationRenderer.render(
        masterFrame: masterFrame,
        frameIndex: frameIndex,
        frameCount: 6,
        width: 32,
        height: 48,
        motion: motion
      )
      XCTAssertEqual(frame.width, 32)
      XCTAssertEqual(frame.height, 48)
    }
  }
}
