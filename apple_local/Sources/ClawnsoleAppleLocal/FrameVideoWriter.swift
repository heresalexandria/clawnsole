@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

enum FrameVideoWriter {
  static func write(
    frames: [URL],
    to outputURL: URL,
    width: Int,
    height: Int,
    frameRate: Int
  ) async throws {
    guard !frames.isEmpty else {
      throw LocalGenerationError.invalidRequest("An animation needs at least one frame.")
    }
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
      ]
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )
    guard writer.canAdd(input) else {
      throw LocalGenerationError.invalidRequest("This device cannot encode the animation.")
    }
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error ?? LocalGenerationError.invalidRequest("Video encoding could not start.")
    }
    writer.startSession(atSourceTime: .zero)

    for (index, frameURL) in frames.enumerated() {
      while !input.isReadyForMoreMediaData {
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 5_000_000)
      }
      let pixelBuffer = try pixelBuffer(
        from: frameURL,
        width: width,
        height: height,
        pool: adaptor.pixelBufferPool
      )
      let presentationTime = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate))
      guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
        throw writer.error ?? LocalGenerationError.invalidRequest("A frame could not be encoded.")
      }
    }
    input.markAsFinished()
    await withCheckedContinuation { continuation in
      writer.finishWriting { continuation.resume() }
    }
    guard writer.status == .completed else {
      throw writer.error ?? LocalGenerationError.invalidRequest("Video encoding failed.")
    }
  }

  private static func pixelBuffer(
    from url: URL,
    width: Int,
    height: Int,
    pool: CVPixelBufferPool?
  ) throws -> CVPixelBuffer {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw LocalGenerationError.invalidRequest("A generated frame could not be decoded.")
    }
    var buffer: CVPixelBuffer?
    let result: CVReturn
    if let pool {
      result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    } else {
      result = CVPixelBufferCreate(
        nil,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        nil,
        &buffer
      )
    }
    guard result == kCVReturnSuccess, let buffer else {
      throw LocalGenerationError.invalidRequest("A video frame buffer could not be allocated.")
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
      let base = CVPixelBufferGetBaseAddress(buffer),
      let context = CGContext(
        data: base,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
      )
    else {
      throw LocalGenerationError.invalidRequest("A generated frame could not be drawn.")
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
  }
}
