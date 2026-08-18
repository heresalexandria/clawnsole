import CoreGraphics
import Foundation

enum AnimationMotionStyle: Equatable, Sendable {
  case tracking
  case bounce
  case vertical
  case pushIn
  case drift
}

struct AnimationFrameTransform: Equatable, Sendable {
  let scale: CGFloat
  let offsetX: CGFloat
  let offsetY: CGFloat
}

struct AnimationMotionPlan: Equatable, Sendable {
  let style: AnimationMotionStyle

  static func forPrompt(_ prompt: String) -> AnimationMotionPlan {
    let normalized = prompt.lowercased()
    if containsAny(
      normalized,
      ["skate", "walk", "run", "ride", "drive", "fly", "swim", "travel", "move"]
    ) {
      return AnimationMotionPlan(style: .tracking)
    }
    if containsAny(normalized, ["jump", "dance", "wave", "bounce", "hop", "nod"]) {
      return AnimationMotionPlan(style: .bounce)
    }
    if containsAny(normalized, ["rise", "fall", "climb", "dive", "float"]) {
      return AnimationMotionPlan(style: .vertical)
    }
    if containsAny(normalized, ["zoom", "approach", "close up", "close-up", "grow"]) {
      return AnimationMotionPlan(style: .pushIn)
    }
    return AnimationMotionPlan(style: .drift)
  }

  func transform(
    frameIndex: Int,
    frameCount: Int,
    width: Int,
    height: Int
  ) -> AnimationFrameTransform {
    let progress = frameCount <= 1 ? 0 : Double(frameIndex) / Double(frameCount)
    let phase = progress * .pi * 2
    let wave = CGFloat(sin(phase))
    let crossWave = CGFloat(cos(phase))
    let width = CGFloat(width)
    let height = CGFloat(height)

    return switch style {
    case .tracking:
      AnimationFrameTransform(
        scale: 1.10,
        offsetX: wave * width * 0.028,
        offsetY: abs(wave) * height * 0.010
      )
    case .bounce:
      AnimationFrameTransform(
        scale: 1.10 + abs(wave) * 0.010,
        offsetX: wave * width * 0.006,
        offsetY: abs(wave) * height * 0.018
      )
    case .vertical:
      AnimationFrameTransform(
        scale: 1.10,
        offsetX: crossWave * width * 0.006,
        offsetY: wave * height * 0.026
      )
    case .pushIn:
      AnimationFrameTransform(
        scale: 1.04 + CGFloat(progress) * 0.08,
        offsetX: 0,
        offsetY: 0
      )
    case .drift:
      AnimationFrameTransform(
        scale: 1.08,
        offsetX: wave * width * 0.012,
        offsetY: crossWave * height * 0.010
      )
    }
  }

  private static func containsAny(_ prompt: String, _ terms: [String]) -> Bool {
    terms.contains { prompt.contains($0) }
  }
}

enum CohesiveAnimationRenderer {
  static func render(
    masterFrame: CGImage,
    frameIndex: Int,
    frameCount: Int,
    width: Int,
    height: Int,
    motion: AnimationMotionPlan
  ) throws -> CGImage {
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw LocalGenerationError.imageEncodingFailed
    }
    let transform = motion.transform(
      frameIndex: frameIndex,
      frameCount: frameCount,
      width: width,
      height: height
    )
    let drawnWidth = CGFloat(width) * transform.scale
    let drawnHeight = CGFloat(height) * transform.scale
    context.interpolationQuality = .high
    context.draw(
      masterFrame,
      in: CGRect(
        x: (CGFloat(width) - drawnWidth) / 2 + transform.offsetX,
        y: (CGFloat(height) - drawnHeight) / 2 + transform.offsetY,
        width: drawnWidth,
        height: drawnHeight
      )
    )
    guard let image = context.makeImage() else {
      throw LocalGenerationError.imageEncodingFailed
    }
    return image
  }
}
