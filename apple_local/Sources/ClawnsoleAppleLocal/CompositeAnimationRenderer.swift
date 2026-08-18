import CoreGraphics
import Foundation

#if canImport(Vision)
  import Vision
#endif

struct AnimationSheetLayout: Equatable, Sendable {
  static let keyframeCount = 24

  let columns: Int
  let rows: Int

  static func forDimensions(width: Int, height: Int) -> AnimationSheetLayout {
    if width == height {
      return AnimationSheetLayout(columns: 5, rows: 5)
    }
    return width < height
      ? AnimationSheetLayout(columns: 6, rows: 4)
      : AnimationSheetLayout(columns: 4, rows: 6)
  }

  var description: String {
    "\(columns)-column by \(rows)-row"
  }

  func keyframes(from sheet: CGImage) throws -> [CGImage] {
    let cellWidth = sheet.width / columns
    let cellHeight = sheet.height / rows
    guard cellWidth > 0, cellHeight > 0 else {
      throw LocalGenerationError.imageEncodingFailed
    }
    return try (0..<Self.keyframeCount).map { index in
      let column = index % columns
      let row = index / columns
      let rect = CGRect(
        x: column * cellWidth,
        y: row * cellHeight,
        width: cellWidth,
        height: cellHeight
      )
      guard let image = sheet.cropping(to: rect) else {
        throw LocalGenerationError.imageEncodingFailed
      }
      return image
    }
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
  static func sheetPrompt(
    lockedPrompt: String,
    layout: AnimationSheetLayout
  ) -> String {
    String(
      "One \(layout.description) sprite sheet with 24 equal cartoon frames, read left to right then top to bottom. \(lockedPrompt) Advance one smooth action in tiny steps. Identical character, clothing, props, setting, camera, palette, and linework in every cell. Thin plain gutters. No text or numbers."
        .prefix(470)
    )
  }

  static func keyframePrompt(originalPrompt: String, keyframeIndex: Int) -> String {
    String(
      "Create only one full-size cartoon frame from reference cell \(keyframeIndex + 1). Preserve its exact character, pose, clothing, props, background, camera, palette, and linework. \(originalPrompt) No grid, panels, collage, text, or redesign."
        .prefix(300)
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
  static func acceptsAtlas(_ keyframes: [CGImage]) -> Bool {
    guard keyframes.count == AnimationSheetLayout.keyframeCount else {
      return false
    }
    #if canImport(Vision)
      do {
        let prints = try keyframes.map(featurePrint)
        var adjacentDistances = [Float]()
        for index in 1..<prints.count {
          adjacentDistances.append(try distance(prints[index - 1], prints[index]))
        }
        let coherentPairs = adjacentDistances.filter { $0 <= 1.20 }.count
        let sorted = adjacentDistances.sorted()
        let median = sorted[sorted.count / 2]
        return coherentPairs >= 18 && median <= 0.95
      } catch {
        return true
      }
    #else
      return true
    #endif
  }

  static func accepts(
    candidate: CGImage,
    previous: CGImage,
    before: CGImage,
    after: CGImage
  ) -> Bool {
    #if canImport(Vision)
      do {
        let candidatePrint = try featurePrint(for: candidate)
        let previousDistance = try distance(candidatePrint, featurePrint(for: previous))
        let beforeDistance = try distance(candidatePrint, featurePrint(for: before))
        let afterDistance = try distance(candidatePrint, featurePrint(for: after))
        let anchorDistance = try distance(featurePrint(for: before), featurePrint(for: after))
        let allowedDistance = min(1.35, max(0.80, anchorDistance * 1.6 + 0.20))
        return previousDistance <= allowedDistance
          || min(beforeDistance, afterDistance) <= allowedDistance
      } catch {
        return true
      }
    #else
      return true
    #endif
  }

  #if canImport(Vision)
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
