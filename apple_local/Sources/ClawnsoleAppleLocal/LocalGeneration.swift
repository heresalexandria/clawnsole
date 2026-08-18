import Foundation
import ImageIO
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#endif

#if canImport(ImagePlayground)
  import ImagePlayground
#endif

#if canImport(FoundationModels)
  import FoundationModels
#endif

public enum LocalGenerationMode: String, Codable, Sendable {
  case image
  case animation
}

public struct LocalGenerationRequest: Codable, Sendable {
  public let requestId: String
  public let mode: LocalGenerationMode
  public let prompt: String
  public let aspectRatio: String
  public let resolution: String
  public let durationSeconds: Int
  public let frameRate: Int
  public let referenceImagePath: String?
  public let outputDirectory: String
  public let modelsDirectory: String

  public init(
    requestId: String,
    mode: LocalGenerationMode,
    prompt: String,
    aspectRatio: String,
    resolution: String,
    durationSeconds: Int,
    frameRate: Int,
    referenceImagePath: String? = nil,
    outputDirectory: String,
    modelsDirectory: String
  ) {
    self.requestId = requestId
    self.mode = mode
    self.prompt = prompt
    self.aspectRatio = aspectRatio
    self.resolution = resolution
    self.durationSeconds = durationSeconds
    self.frameRate = frameRate
    self.referenceImagePath = referenceImagePath
    self.outputDirectory = outputDirectory
    self.modelsDirectory = modelsDirectory
  }

  public var frameCount: Int {
    mode == .image ? 1 : durationSeconds * frameRate
  }

  public func dimensions() throws -> (width: Int, height: Int) {
    let large = resolution == "fhd"
    return switch aspectRatio {
    case "16:9": large ? (768, 448) : (512, 320)
    case "4:3": large ? (768, 576) : (512, 384)
    case "1:1": large ? (768, 768) : (512, 512)
    case "3:4": large ? (576, 768) : (384, 512)
    case "9:16": large ? (448, 768) : (320, 512)
    default: throw LocalGenerationError.invalidRequest("Unsupported aspect ratio.")
    }
  }

  public func validate() throws {
    guard !requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw LocalGenerationError.invalidRequest("A request id is required.")
    }
    guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw LocalGenerationError.invalidRequest("A prompt is required.")
    }
    guard (1...8).contains(durationSeconds) else {
      throw LocalGenerationError.invalidRequest("Duration must be between 1 and 8 seconds.")
    }
    guard (1...6).contains(frameRate) else {
      throw LocalGenerationError.invalidRequest("Frame rate must be between 1 and 6 fps.")
    }
    guard frameCount <= 48 else {
      throw LocalGenerationError.invalidRequest("An animation can contain at most 48 frames.")
    }
    _ = try dimensions()
  }
}

public struct LocalGenerationProgress: Codable, Sendable {
  public let status: String
  public let progress: Double
  public let message: String
  public let resultPath: String?
  public let contentType: String?
  public let expandedPrompt: String?
  public let error: String?

  public init(
    status: String,
    progress: Double,
    message: String,
    resultPath: String? = nil,
    contentType: String? = nil,
    expandedPrompt: String? = nil,
    error: String? = nil
  ) {
    self.status = status
    self.progress = progress
    self.message = message
    self.resultPath = resultPath
    self.contentType = contentType
    self.expandedPrompt = expandedPrompt
    self.error = error
  }
}

public enum LocalGenerationError: LocalizedError {
  case invalidRequest(String)
  case unavailable
  case noImageReturned
  case imageEncodingFailed

  public var errorDescription: String? {
    switch self {
    case .invalidRequest(let message): message
    case .unavailable:
      "Apple Intelligence image creation is not available on this device."
    case .noImageReturned: "Apple Intelligence did not return an image."
    case .imageEncodingFailed: "A generated image could not be encoded."
    }
  }
}

public enum AnimationPromptPlan {
  public static func fallbackLock(for prompt: String) -> String {
    let direction = String(prompt.prefix(420))
    return String(
      """
      Cohesive hand-drawn cartoon: \(direction)

      CONTINUITY LOCK: Keep identical characters, faces, proportions, wardrobe, props, palette, line weight, shading, lighting, camera, composition, set geography, scale, and time of day. Advance only the requested action through small plausible poses. No text, logos, cuts, camera jumps, new objects, duplicate limbs, or identity changes.
      """.prefix(600)
    )
  }

  public static func framePrompt(
    lockedPrompt: String,
    frameIndex: Int,
    frameCount: Int,
    frameRate: Int
  ) -> String {
    let progress = frameCount <= 1 ? 0 : Double(frameIndex) / Double(frameCount - 1)
    let time = Double(frameIndex) / Double(frameRate)
    return """
      \(lockedPrompt)

      FRAME INSTRUCTION: Draw frame \(frameIndex + 1) of \(frameCount) at \(String(format: "%.3f", time)) seconds, \(String(format: "%.1f", progress * 100))% through the action. Advance one smooth increment. Preserve every continuity-locked detail. Return one finished frame, not a storyboard.
      """
  }
}

public struct LocalGenerationEngine: Sendable {
  public init() {}

  public static func isAvailable() async -> Bool {
    #if canImport(ImagePlayground)
      if #available(iOS 18.4, macOS 15.4, *) {
        do {
          let creator = try await ImageCreator()
          return creator.availableStyles.contains(.animation)
            && creator.availableStyles.contains(.illustration)
        } catch {
          return false
        }
      }
    #endif
    return false
  }

  public func generate(
    _ request: LocalGenerationRequest,
    progress: @escaping @Sendable (LocalGenerationProgress) -> Void
  ) async throws -> URL {
    try request.validate()
    #if canImport(AppKit)
      let activationWindow = await MainActor.run {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.finishLaunching()
        application.unhide(nil)
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
          styleMask: [.titled],
          backing: .buffered,
          defer: false
        )
        window.title = "Clawnsole · Apple Local"
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let title = NSTextField(labelWithString: "Creating with Apple Intelligence…")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.alignment = .center
        let detail = NSTextField(
          wrappingLabelWithString:
            "Keep this window in front until generation finishes. Your result will appear in Clawnsole automatically."
        )
        detail.alignment = .center
        detail.textColor = .secondaryLabelColor
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)
        let stack = NSStackView(views: [title, detail, indicator])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 20, right: 28)
        window.contentView = stack
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        application.activate(ignoringOtherApps: true)
        return window
      }
      try await Task.sleep(nanoseconds: 300_000_000)
      guard await MainActor.run(body: { NSApplication.shared.isActive }) else {
        throw LocalGenerationError.invalidRequest(
          "Apple Intelligence image creation requires Clawnsole to be in the foreground."
        )
      }
      defer { Task { @MainActor in activationWindow.orderOut(nil) } }
    #endif
    let outputDirectory = URL(fileURLWithPath: request.outputDirectory, isDirectory: true)
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )
    let dimensions = try request.dimensions()

    #if canImport(ImagePlayground)
      guard #available(iOS 18.4, macOS 15.4, *) else {
        throw LocalGenerationError.unavailable
      }
      progress(.init(status: "Pending", progress: 1, message: "Opening Apple Intelligence"))
      let creator = try await ImageCreator()
      let style: ImagePlaygroundStyle = request.mode == .image ? .illustration : .animation
      guard creator.availableStyles.contains(style) else {
        throw LocalGenerationError.unavailable
      }
    #else
      throw LocalGenerationError.unavailable
    #endif

    let lockedPrompt = await expandedPrompt(for: request)
    progress(
      .init(
        status: "Pending",
        progress: 4,
        message: "Locked the visual direction",
        expandedPrompt: lockedPrompt
      )
    )

    var frameURLs = [URL]()
    var previousImagePath = request.referenceImagePath
    for frameIndex in 0..<request.frameCount {
      try Task.checkCancellation()
      let prompt =
        request.mode == .image
        ? lockedPrompt
        : AnimationPromptPlan.framePrompt(
          lockedPrompt: lockedPrompt,
          frameIndex: frameIndex,
          frameCount: request.frameCount,
          frameRate: request.frameRate
        )
      progress(
        .init(
          status: "Pending",
          progress: 5 + (Double(frameIndex) / Double(request.frameCount)) * 88,
          message: "Generating frame \(frameIndex + 1) of \(request.frameCount)"
        )
      )
      #if canImport(ImagePlayground)
        var concepts = [ImagePlaygroundConcept.text(prompt)]
        if let previousImagePath,
          let reference = imageConcept(at: URL(fileURLWithPath: previousImagePath))
        {
          concepts.append(reference)
        }
        var generatedImage: CGImage?
        let images = creator.images(for: concepts, style: style, limit: 1)
        for try await result in images {
          generatedImage = result.cgImage
          break
        }
        guard let generatedImage else { throw LocalGenerationError.noImageReturned }
        let image = try fittedImage(
          generatedImage,
          width: dimensions.width,
          height: dimensions.height
        )
      #else
        throw LocalGenerationError.unavailable
      #endif
      let frameURL = outputDirectory.appendingPathComponent(
        String(format: "frame-%04d.png", frameIndex)
      )
      try writePNG(image, to: frameURL)
      frameURLs.append(frameURL)
      previousImagePath = frameURL.path
    }

    if request.mode == .image {
      let resultURL = outputDirectory.appendingPathComponent("result.png")
      if FileManager.default.fileExists(atPath: resultURL.path) {
        try FileManager.default.removeItem(at: resultURL)
      }
      try FileManager.default.moveItem(at: frameURLs[0], to: resultURL)
      progress(
        .init(
          status: "Ready",
          progress: 100,
          message: "Local image ready",
          resultPath: resultURL.path,
          contentType: "image/png",
          expandedPrompt: lockedPrompt
        )
      )
      return resultURL
    }

    progress(.init(status: "Pending", progress: 95, message: "Encoding animation"))
    let resultURL = outputDirectory.appendingPathComponent("result.mp4")
    try await FrameVideoWriter.write(
      frames: frameURLs,
      to: resultURL,
      width: dimensions.width,
      height: dimensions.height,
      frameRate: request.frameRate
    )
    for frameURL in frameURLs {
      try? FileManager.default.removeItem(at: frameURL)
    }
    progress(
      .init(
        status: "Ready",
        progress: 100,
        message: "Local animation ready",
        resultPath: resultURL.path,
        contentType: "video/mp4",
        expandedPrompt: lockedPrompt
      )
    )
    return resultURL
  }

  #if canImport(ImagePlayground)
    @available(iOS 18.1, macOS 15.1, *)
    private func imageConcept(at url: URL) -> ImagePlaygroundConcept? {
      guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        return nil
      }
      return .image(image)
    }
  #endif

  private func fittedImage(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
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
      throw LocalGenerationError.imageEncodingFailed
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
    else {
      throw LocalGenerationError.imageEncodingFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw LocalGenerationError.imageEncodingFailed
    }
  }

  private func expandedPrompt(for request: LocalGenerationRequest) async -> String {
    if request.mode == .image {
      return String(request.prompt.prefix(900))
    }
    let fallback = AnimationPromptPlan.fallbackLock(for: request.prompt)
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let model = SystemLanguageModel.default
        if model.isAvailable {
          do {
            let session = LanguageModelSession(
              model: model,
              instructions: """
                You are a production animation art director. Expand short requests into one dense visual continuity specification for an image model. Lock character model sheets, wardrobe, palette, line style, materials, set geography, lighting, camera, composition, and a gradual action arc. Never introduce facts that conflict with the request. Stay under 60 words and output only the reusable image prompt.
                """
            )
            let response = try await session.respond(
              to:
                "Expand and continuity-lock this request for \(request.frameCount) frame(s): \(request.prompt)"
            )
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { return String(content.prefix(600)) }
          } catch {
            // The deterministic lock remains usable when Apple Intelligence is busy.
          }
        }
      }
    #endif
    return fallback
  }
}
