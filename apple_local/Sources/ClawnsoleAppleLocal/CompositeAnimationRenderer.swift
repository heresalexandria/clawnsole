import CoreGraphics
import Foundation

#if canImport(Vision)
  import Vision
#endif

enum AnimationAnchorPlan {
  /// Dense sprite-sheet prompts are not reliably honored by Image Playground.
  /// Generate one full-size anchor for roughly every four output frames instead.
  static func anchorCount(forFrameCount frameCount: Int) -> Int {
    guard frameCount > 1 else { return max(1, frameCount) }
    return min(frameCount, max(2, Int(ceil(Double(frameCount) / 4.0)) + 1))
  }
}

struct AnimationTimelineSample: Equatable, Sendable {
  let beforeIndex: Int
  let afterIndex: Int
  let fraction: Double

  var isKeyframe: Bool {
    beforeIndex == afterIndex
  }

  static func at(frameIndex: Int, frameCount: Int, keyframeCount: Int)
    -> AnimationTimelineSample
  {
    guard frameCount > 1, keyframeCount > 1 else {
      return AnimationTimelineSample(beforeIndex: 0, afterIndex: 0, fraction: 0)
    }
    let position =
      Double(frameIndex) / Double(frameCount - 1) * Double(keyframeCount - 1)
    let rounded = position.rounded()
    if abs(position - rounded) < 0.000_001 {
      let index = min(keyframeCount - 1, max(0, Int(rounded)))
      return AnimationTimelineSample(
        beforeIndex: index,
        afterIndex: index,
        fraction: 0
      )
    }
    let before = min(keyframeCount - 1, max(0, Int(floor(position))))
    let after = min(keyframeCount - 1, before + 1)
    return AnimationTimelineSample(
      beforeIndex: before,
      afterIndex: after,
      fraction: position - floor(position)
    )
  }
}

enum CompositeAnimationPromptPlan {
  static func anchorOnlyPrompt(
    lockedPrompt: String,
    originalPrompt: String,
    fraction: Double
  ) -> String {
    let percent = Int((fraction * 100).rounded())
    return String(
      "Create only one full-size cartoon frame, not a grid. The reference board shows the immutable design master top left and the previous anchor twice. At \(percent)% of the action, advance the pose clearly but preserve the exact character, clothing, props, setting, camera, palette, and linework. \(lockedPrompt) \(originalPrompt) No text or collage."
        .prefix(430)
    )
  }

  static func targetOnlyPrompt(originalPrompt: String, fraction: Double) -> String {
    let percent = Int((fraction * 100).rounded())
    return String(
      "Create only the missing full-size cartoon frame, not a grid. The reference is a 2 by 2 continuity board: earlier anchor top left, later anchor top right, previous frame bottom left, blank target bottom right. Continue \(percent)% between anchors. Preserve exact design and scene. \(originalPrompt) No text or collage."
        .prefix(360)
    )
  }

  static func completedBoardPrompt(fraction: Double) -> String {
    let percent = Int((fraction * 100).rounded())
    return String(
      "Complete the blank bottom-right cell of this 2 by 2 cartoon continuity board at \(percent)% between the top anchors. Keep the same character, scene, camera, palette, and linework. Return the completed board with the other three cells unchanged. No text."
        .prefix(280)
    )
  }

  static func completedAnchorBoardPrompt(fraction: Double) -> String {
    let percent = Int((fraction * 100).rounded())
    return String(
      "Complete only the blank bottom-right cell of this 2 by 2 cartoon board. The top-left cell is the immutable design master; the other filled cells are the previous anchor. Draw the same character and scene at \(percent)% of the requested action. Return the completed board unchanged outside that cell. No text."
        .prefix(320)
    )
  }
}

enum CompositeAnimationRenderer {
  private static let boardSize = 1024
  private static let gutter = 20

  static func continuityBoard(
    before: CGImage,
    after: CGImage,
    previous: CGImage
  ) throws -> CGImage {
    guard
      let context = CGContext(
        data: nil,
        width: boardSize,
        height: boardSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw LocalGenerationError.imageEncodingFailed
    }

    context.setFillColor(CGColor(gray: 0.10, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: boardSize, height: boardSize))
    let half = boardSize / 2
    let inset = gutter
    let cellSize = half - inset * 2
    drawAspectFill(
      before,
      in: CGRect(x: inset, y: half + inset, width: cellSize, height: cellSize),
      context: context
    )
    drawAspectFill(
      after,
      in: CGRect(x: half + inset, y: half + inset, width: cellSize, height: cellSize),
      context: context
    )
    drawAspectFill(
      previous,
      in: CGRect(x: inset, y: inset, width: cellSize, height: cellSize),
      context: context
    )
    context.setFillColor(CGColor(gray: 0.82, alpha: 1))
    context.fill(
      CGRect(x: half + inset, y: inset, width: cellSize, height: cellSize)
    )
    context.setStrokeColor(CGColor(gray: 0.58, alpha: 1))
    context.setLineWidth(5)
    context.stroke(
      CGRect(x: half + inset, y: inset, width: cellSize, height: cellSize)
    )

    guard let board = context.makeImage() else {
      throw LocalGenerationError.imageEncodingFailed
    }
    return board
  }

  static func targetCell(from completedBoard: CGImage) throws -> CGImage {
    let halfWidth = completedBoard.width / 2
    let halfHeight = completedBoard.height / 2
    let horizontalInset = max(1, completedBoard.width * gutter / boardSize)
    let verticalInset = max(1, completedBoard.height * gutter / boardSize)
    let rect = CGRect(
      x: halfWidth + horizontalInset,
      y: halfHeight + verticalInset,
      width: halfWidth - horizontalInset * 2,
      height: halfHeight - verticalInset * 2
    )
    guard let target = completedBoard.cropping(to: rect) else {
      throw LocalGenerationError.imageEncodingFailed
    }
    return target
  }

  private static func drawAspectFill(
    _ image: CGImage,
    in rect: CGRect,
    context: CGContext
  ) {
    let scale = max(
      rect.width / CGFloat(image.width),
      rect.height / CGFloat(image.height)
    )
    let width = CGFloat(image.width) * scale
    let height = CGFloat(image.height) * scale
    context.interpolationQuality = .high
    context.saveGState()
    context.clip(to: rect)
    context.draw(
      image,
      in: CGRect(
        x: rect.midX - width / 2,
        y: rect.midY - height / 2,
        width: width,
        height: height
      )
    )
    context.restoreGState()
  }
}

enum AnimationFrameConsistency {
  static func looksLikeContinuityBoard(_ image: CGImage) -> Bool {
    let sampleSize = 64
    var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
    guard
      let context = CGContext(
        data: &pixels,
        width: sampleSize,
        height: sampleSize,
        bitsPerComponent: 8,
        bytesPerRow: sampleSize * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return false
    }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

    func luminance(x: Int, y: Int) -> Double {
      let offset = (y * sampleSize + x) * 4
      return
        Double(pixels[offset]) * 0.2126 + Double(pixels[offset + 1]) * 0.7152
        + Double(pixels[offset + 2]) * 0.0722
    }
    func verticalAverage(columns: ClosedRange<Int>) -> Double {
      var total = 0.0
      var count = 0
      for x in columns {
        for y in 4..<(sampleSize - 4) {
          total += luminance(x: x, y: y)
          count += 1
        }
      }
      return total / Double(count)
    }
    func horizontalAverage(rows: ClosedRange<Int>) -> Double {
      var total = 0.0
      var count = 0
      for y in rows {
        for x in 4..<(sampleSize - 4) {
          total += luminance(x: x, y: y)
          count += 1
        }
      }
      return total / Double(count)
    }

    let verticalSeam = verticalAverage(columns: 31...32)
    let verticalNeighbors =
      (verticalAverage(columns: 26...28) + verticalAverage(columns: 35...37)) / 2
    let horizontalSeam = horizontalAverage(rows: 31...32)
    let horizontalNeighbors =
      (horizontalAverage(rows: 26...28) + horizontalAverage(rows: 35...37)) / 2
    return verticalNeighbors > 20 && horizontalNeighbors > 20
      && verticalSeam < verticalNeighbors * 0.68
      && horizontalSeam < horizontalNeighbors * 0.68
  }

  /// Selects the most visually continuous usable candidate. Feature-print
  /// distance is deliberately a ranking signal, never a validity gate: a large
  /// pose change can be correct for an action such as jumping or turning.
  static func bestCandidate(
    from candidates: [CGImage],
    previous: CGImage,
    before: CGImage,
    after: CGImage
  ) -> CGImage? {
    guard let firstCandidate = candidates.first else { return nil }
    #if canImport(Vision)
      do {
        let previousPrint = try featurePrint(for: previous)
        let beforePrint = try featurePrint(for: before)
        let afterPrint = try featurePrint(for: after)
        return try candidates.min { first, second in
          try continuityScore(
            for: first,
            previous: previousPrint,
            before: beforePrint,
            after: afterPrint
          )
            < continuityScore(
              for: second,
              previous: previousPrint,
              before: beforePrint,
              after: afterPrint
            )
        }
      } catch {
        return firstCandidate
      }
    #else
      return firstCandidate
    #endif
  }

  #if canImport(Vision)
    private static func continuityScore(
      for candidate: CGImage,
      previous: VNFeaturePrintObservation,
      before: VNFeaturePrintObservation,
      after: VNFeaturePrintObservation
    ) throws -> Float {
      let candidatePrint = try featurePrint(for: candidate)
      return try distance(candidatePrint, previous) * 0.5
        + distance(candidatePrint, before) * 0.25
        + distance(candidatePrint, after) * 0.25
    }

    private static func featurePrint(for image: CGImage) throws -> VNFeaturePrintObservation {
      let request = VNGenerateImageFeaturePrintRequest()
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
      guard let observation = request.results?.first as? VNFeaturePrintObservation else {
        throw LocalGenerationError.imageEncodingFailed
      }
      return observation
    }

    private static func distance(
      _ first: VNFeaturePrintObservation,
      _ second: VNFeaturePrintObservation
    ) throws -> Float {
      var value: Float = 0
      try first.computeDistance(&value, to: second)
      return value
    }
  #endif
}
