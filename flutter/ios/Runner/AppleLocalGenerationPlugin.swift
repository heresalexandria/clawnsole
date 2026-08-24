@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Flutter
import Foundation
import ImageIO
import ImagePlayground
import UniformTypeIdentifiers

private enum AppleLocalMode: String {
  case image
  case sequence
}

private enum AppleLocalError: LocalizedError {
  case invalidRequest(String)
  case unavailable
  case noImageReturned
  case imageEncodingFailed

  var errorDescription: String? {
    switch self {
    case .invalidRequest(let message): message
    case .unavailable:
      "Apple Intelligence image creation is unavailable on this device."
    case .noImageReturned:
      "Apple Intelligence did not return an image."
    case .imageEncodingFailed:
      "A generated image could not be encoded."
    }
  }
}

private struct AppleLocalRequest: Sendable {
  let requestId: String
  let mode: AppleLocalMode
  let prompt: String
  let aspectRatio: String
  let resolution: String
  let durationSeconds: Int
  let outputDirectory: URL

  init(arguments: [String: Any]) throws {
    let rawId =
      (arguments["requestId"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ) ?? UUID().uuidString
    let safeCharacters = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-_")
    )
    guard
      !rawId.isEmpty,
      rawId.rangeOfCharacter(from: safeCharacters.inverted) == nil
    else {
      throw AppleLocalError.invalidRequest("The local request id is invalid.")
    }
    guard let mode = AppleLocalMode(rawValue: arguments["mode"] as? String ?? "")
    else {
      throw AppleLocalError.invalidRequest("The local generation mode is invalid.")
    }
    let prompt =
      (arguments["prompt"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ) ?? ""
    guard !prompt.isEmpty, prompt.count <= 900 else {
      throw AppleLocalError.invalidRequest(
        "The prompt must contain between 1 and 900 characters."
      )
    }
    let aspectRatio = arguments["aspectRatio"] as? String ?? ""
    guard ["16:9", "4:3", "1:1", "3:4", "9:16"].contains(aspectRatio) else {
      throw AppleLocalError.invalidRequest("The aspect ratio is not supported.")
    }
    let resolution = arguments["resolution"] as? String ?? ""
    guard ["hd", "fhd"].contains(resolution) else {
      throw AppleLocalError.invalidRequest("The image size is not supported.")
    }
    let duration = arguments["durationSeconds"] as? Int ?? 0
    guard mode == .image ? duration == 1 : (1...8).contains(duration) else {
      throw AppleLocalError.invalidRequest(
        "Image sequences must be between 1 and 8 seconds."
      )
    }
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("Clawnsole/AppleLocal/jobs", isDirectory: true)

    requestId = rawId
    self.mode = mode
    self.prompt = prompt
    self.aspectRatio = aspectRatio
    self.resolution = resolution
    durationSeconds = duration
    outputDirectory = support.appendingPathComponent(rawId, isDirectory: true)
  }

  var frameCount: Int { mode == .image ? 1 : durationSeconds }

  var dimensions: (width: Int, height: Int) {
    let large = resolution == "fhd"
    return switch aspectRatio {
    case "16:9": large ? (768, 448) : (512, 320)
    case "4:3": large ? (768, 576) : (512, 384)
    case "1:1": large ? (768, 768) : (512, 512)
    case "3:4": large ? (576, 768) : (384, 512)
    default: large ? (448, 768) : (320, 512)
    }
  }

  func promptForFrame(_ index: Int) -> String {
    guard mode == .sequence else { return prompt }
    return """
      (prompt)

      Create frame (index + 1) of (frameCount) in one continuous visual sequence, at second (index + 1). Keep the same subjects, appearance, composition, setting, palette, lighting, and camera. Advance the action by one clear step. Return one finished image, never a storyboard, collage, caption, or logo.
      """
  }
}

private struct AppleLocalProgress: Codable, Sendable {
  let status: String
  let progress: Double
  let message: String
  var resultPath: String?
  var contentType: String?
  var error: String?
}

private struct AppleLocalGenerator: Sendable {
  static func isAvailable() async -> Bool {
    guard #available(iOS 18.4, *) else { return false }
    do {
      let creator = try await ImageCreator()
      return creator.availableStyles.contains(.illustration)
        && creator.availableStyles.contains(.animation)
    } catch {
      return false
    }
  }

  func generate(
    _ request: AppleLocalRequest,
    progress: @escaping @Sendable (AppleLocalProgress) -> Void
  ) async throws {
    guard #available(iOS 18.4, *) else { throw AppleLocalError.unavailable }
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: request.outputDirectory.path) {
      try fileManager.removeItem(at: request.outputDirectory)
    }
    try fileManager.createDirectory(
      at: request.outputDirectory,
      withIntermediateDirectories: true
    )

    progress(
      AppleLocalProgress(
        status: "Pending",
        progress: 1,
        message: "Opening Apple Intelligence"
      )
    )
    let creator = try await ImageCreator()
    let style: ImagePlaygroundStyle = request.mode == .image ? .illustration : .animation
    guard creator.availableStyles.contains(style) else {
      throw AppleLocalError.unavailable
    }

    let dimensions = request.dimensions
    var frameURLs = [URL]()
    var previousImage: CGImage?
    for index in 0..<request.frameCount {
      try Task.checkCancellation()
      progress(
        AppleLocalProgress(
          status: "Pending",
          progress: 4 + (Double(index) / Double(request.frameCount)) * 90,
          message: "Generating image (index + 1) of (request.frameCount)"
        )
      )
      var concepts = [ImagePlaygroundConcept.text(request.promptForFrame(index))]
      if let previousImage { concepts.append(.image(previousImage)) }
      var generated: CGImage?
      let images = creator.images(for: concepts, style: style, limit: 1)
      for try await result in images {
        generated = result.cgImage
        break
      }
      guard let generated else { throw AppleLocalError.noImageReturned }
      let fitted = try fittedImage(
        generated,
        width: dimensions.width,
        height: dimensions.height
      )
      let frameURL = request.outputDirectory.appendingPathComponent(
        String(format: "frame-%04d.png", index)
      )
      try writePNG(fitted, to: frameURL)
      frameURLs.append(frameURL)
      previousImage = fitted
    }

    if request.mode == .image {
      let resultURL = request.outputDirectory.appendingPathComponent("result.png")
      try fileManager.moveItem(at: frameURLs[0], to: resultURL)
      progress(
        AppleLocalProgress(
          status: "Ready",
          progress: 100,
          message: "Apple image ready",
          resultPath: resultURL.path,
          contentType: "image/png"
        )
      )
      return
    }

    progress(
      AppleLocalProgress(
        status: "Pending",
        progress: 96,
        message: "Encoding the image sequence"
      )
    )
    let resultURL = request.outputDirectory.appendingPathComponent("result.mp4")
    try await writeVideo(
      frames: frameURLs,
      to: resultURL,
      width: dimensions.width,
      height: dimensions.height
    )
    for frameURL in frameURLs { try? fileManager.removeItem(at: frameURL) }
    progress(
      AppleLocalProgress(
        status: "Ready",
        progress: 100,
        message: "Apple image sequence ready",
        resultPath: resultURL.path,
        contentType: "video/mp4"
      )
    )
  }

  private func fittedImage(
    _ image: CGImage,
    width: Int,
    height: Int
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
    else { throw AppleLocalError.imageEncodingFailed }
    let scale = max(
      CGFloat(width) / CGFloat(image.width),
      CGFloat(height) / CGFloat(image.height)
    )
    let drawnWidth = CGFloat(image.width) * scale
    let drawnHeight = CGFloat(image.height) * scale
    context.interpolationQuality = .high
    context.draw(
      image,
      in: CGRect(
        x: (CGFloat(width) - drawnWidth) / 2,
        y: (CGFloat(height) - drawnHeight) / 2,
        width: drawnWidth,
        height: drawnHeight
      )
    )
    guard let result = context.makeImage() else {
      throw AppleLocalError.imageEncodingFailed
    }
    return result
  }

  private func writePNG(_ image: CGImage, to url: URL) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else { throw AppleLocalError.imageEncodingFailed }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw AppleLocalError.imageEncodingFailed
    }
  }

  private func writeVideo(
    frames: [URL],
    to outputURL: URL,
    width: Int,
    height: Int
  ) async throws {
    guard !frames.isEmpty else {
      throw AppleLocalError.invalidRequest("An image sequence needs at least one frame.")
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
      throw AppleLocalError.invalidRequest("This device cannot encode the sequence.")
    }
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error
        ?? AppleLocalError.invalidRequest("Video encoding could not start.")
    }
    writer.startSession(atSourceTime: .zero)

    for (index, frameURL) in frames.enumerated() {
      while !input.isReadyForMoreMediaData {
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 5_000_000)
      }
      let buffer = try pixelBuffer(
        from: frameURL,
        width: width,
        height: height,
        pool: adaptor.pixelBufferPool
      )
      guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 1))
      else {
        throw writer.error
          ?? AppleLocalError.invalidRequest("An image could not be encoded.")
      }
    }
    input.markAsFinished()
    writer.endSession(
      atSourceTime: CMTime(value: Int64(frames.count), timescale: 1)
    )
    await withCheckedContinuation { continuation in
      writer.finishWriting { continuation.resume() }
    }
    guard writer.status == .completed else {
      throw writer.error
        ?? AppleLocalError.invalidRequest("Video encoding failed.")
    }
  }

  private func pixelBuffer(
    from url: URL,
    width: Int,
    height: Int,
    pool: CVPixelBufferPool?
  ) throws -> CVPixelBuffer {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw AppleLocalError.invalidRequest("A generated image could not be decoded.")
    }
    var buffer: CVPixelBuffer?
    let result = pool == nil
      ? CVPixelBufferCreate(
        nil,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        nil,
        &buffer
      )
      : CVPixelBufferPoolCreatePixelBuffer(nil, pool!, &buffer)
    guard result == kCVReturnSuccess, let buffer else {
      throw AppleLocalError.invalidRequest("A video frame buffer could not be allocated.")
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
      throw AppleLocalError.invalidRequest("A generated image could not be drawn.")
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
  }
}

private actor AppleLocalJobManager {
  private var jobs = [String: AppleLocalProgress]()

  func start(arguments: [String: Any]) throws -> String {
    let request = try AppleLocalRequest(arguments: arguments)
    jobs[request.requestId] = AppleLocalProgress(
      status: "Pending",
      progress: 0,
      message: "Queued on this device"
    )
    Task {
      do {
        try await AppleLocalGenerator().generate(request) { update in
          Task { await self.record(update, for: request.requestId) }
        }
      } catch {
        record(
          AppleLocalProgress(
            status: "Error",
            progress: 0,
            message: "Apple generation failed",
            error: error.localizedDescription
          ),
          for: request.requestId
        )
      }
    }
    return request.requestId
  }

  func progress(for jobId: String) -> AppleLocalProgress? { jobs[jobId] }

  private func record(_ progress: AppleLocalProgress, for jobId: String) {
    jobs[jobId] = progress
  }
}

final class AppleLocalGenerationPlugin {
  private let manager = AppleLocalJobManager()

  func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.clawnsole/apple_local",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        return result(FlutterError(code: "unavailable", message: nil, details: nil))
      }
      switch call.method {
      case "isAvailable":
        #if targetEnvironment(simulator)
          result(false)
        #else
          Task {
            let available = await AppleLocalGenerator.isAvailable()
            await MainActor.run { result(available) }
          }
        #endif
      case "submit":
        guard let arguments = call.arguments as? [String: Any] else {
          return result(
            FlutterError(
              code: "invalid_request",
              message: "Apple Intelligence needs a request object.",
              details: nil
            )
          )
        }
        Task {
          do {
            let jobId = try await self.manager.start(arguments: arguments)
            await MainActor.run { result(["jobId": jobId, "status": "Pending"]) }
          } catch {
            await MainActor.run {
              result(
                FlutterError(
                  code: "local_generation_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      case "poll":
        guard
          let arguments = call.arguments as? [String: Any],
          let jobId = arguments["jobId"] as? String
        else {
          return result(
            FlutterError(
              code: "invalid_request",
              message: "Apple Intelligence needs a local job id.",
              details: nil
            )
          )
        }
        Task {
          guard let update = await self.manager.progress(for: jobId) else {
            return await MainActor.run {
              result([
                "status": "Error",
                "progress": 0,
                "error":
                  "This local job is no longer running. It may have been interrupted when the app closed.",
              ])
            }
          }
          do {
            let data = try JSONEncoder().encode(update)
            let payload = try JSONSerialization.jsonObject(with: data)
            await MainActor.run { result(payload) }
          } catch {
            await MainActor.run {
              result(
                FlutterError(
                  code: "invalid_status",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
