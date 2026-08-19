import Foundation
import ImageIO
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#endif

#if canImport(UIKit)
  import UIKit
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
  case imageCreationFailed(
    frame: Int,
    frameCount: Int,
    attempts: Int,
    retriedWithoutReference: Bool,
    reason: String
  )

  public var failureProgress: Double? {
    switch self {
    case .imageCreationFailed(let frame, let frameCount, _, _, _):
      guard frameCount > 0 else { return 5 }
      return 5 + (Double(frame - 1) / Double(frameCount)) * 88
    default: return nil
    }
  }

  public var errorDescription: String? {
    switch self {
    case .invalidRequest(let message): message
    case .unavailable:
      "Apple Intelligence image creation is not available on this device."
    case .noImageReturned: "Apple Intelligence did not return an image."
    case .imageEncodingFailed: "A generated image could not be encoded."
    case .imageCreationFailed(
      let frame,
      let frameCount,
      let attempts,
      let retriedWithoutReference,
      let reason
    ):
      "Apple Image Playground could not create frame \(frame) of \(frameCount) after \(attempts) attempts. \(retriedWithoutReference ? "Clawnsole also retried without the reference frame. " : "")\(reason)"
    }
  }
}

public struct FrameGenerationAttempt: Equatable, Sendable {
  public let prompt: String
  public let includeReference: Bool
  public let useFallbackStyle: Bool

  public init(prompt: String, includeReference: Bool, useFallbackStyle: Bool = false) {
    self.prompt = prompt
    self.includeReference = includeReference
    self.useFallbackStyle = useFallbackStyle
  }
}

public enum AnimationPromptPlan {
  public static func validatedExpandedLock(_ candidate: String) -> String? {
    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    let words = trimmed.split(whereSeparator: { $0.isWhitespace })
    guard
      !trimmed.isEmpty,
      !trimmed.contains("\n"),
      !trimmed.contains("**"),
      !trimmed.contains("#"),
      !trimmed.hasPrefix("-"),
      trimmed.range(of: #"^\d+[.)]"#, options: .regularExpression) == nil,
      (8...45).contains(words.count)
    else {
      return nil
    }
    return String(trimmed.prefix(320))
  }

  public static func originalPromptFallback(for prompt: String) -> String {
    String(
      prompt
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
        .prefix(180)
    )
  }

  public static func fallbackLock(for prompt: String) -> String {
    let direction = String(prompt.prefix(170))
    return String(
      """
      Hand-drawn cartoon: \(direction) Keep characters, faces, proportions, wardrobe, props, palette, linework, lighting, camera, and setting identical. Advance only the action in small poses. No text, cuts, extra limbs, or identity changes.
      """.prefix(320)
    )
  }

  public static func masterFramePrompt(lockedPrompt: String) -> String {
    return String(
      """
      \(lockedPrompt)

      Draw one cohesive first frame for a short cartoon animation. Show one clear subject in a recognizable starting pose just before the requested action advances. Keep the subject and important props inside the center 80%. Use one stable background, one composition, and one finished image. No storyboard, panels, text, duplicate subjects, or alternate designs.
      """.prefix(480)
    )
  }

  public static func compactMasterFramePrompt(lockedPrompt: String) -> String {
    return String(
      "One cohesive cartoon first frame. \(lockedPrompt) Recognizable starting pose, centered subject, stable simple background. One image only; no panels, text, duplicates, or alternate designs."
        .prefix(300)
    )
  }

  public static func attempts(
    lockedPrompt: String,
    originalPrompt: String,
    hasReference: Bool
  ) -> [FrameGenerationAttempt] {
    let detailed = masterFramePrompt(lockedPrompt: lockedPrompt)
    let compact = compactMasterFramePrompt(lockedPrompt: lockedPrompt)
    let original = originalPromptFallback(for: originalPrompt)
    if hasReference {
      return [
        FrameGenerationAttempt(prompt: detailed, includeReference: true),
        FrameGenerationAttempt(prompt: compact, includeReference: true),
        FrameGenerationAttempt(
          prompt: original,
          includeReference: false,
          useFallbackStyle: true
        ),
      ]
    }
    return [
      FrameGenerationAttempt(prompt: detailed, includeReference: false),
      FrameGenerationAttempt(prompt: compact, includeReference: false),
      FrameGenerationAttempt(
        prompt: original,
        includeReference: false,
        useFallbackStyle: true
      ),
    ]
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
    #if canImport(UIKit)
      guard await waitForForegroundApplication() else {
        throw LocalGenerationError.invalidRequest(
          "Apple Intelligence image creation requires Clawnsole to be open in the foreground."
        )
      }
      let previousIdleTimerSetting = await MainActor.run {
        let previous = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        return previous
      }
      defer {
        Task { @MainActor in
          UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting
        }
      }
    #endif
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
      let foregroundKeeper = Task { @MainActor in
        while !Task.isCancelled {
          NSApplication.shared.activate(ignoringOtherApps: true)
          activationWindow.orderFrontRegardless()
          try? await Task.sleep(nanoseconds: 400_000_000)
        }
      }
      defer { foregroundKeeper.cancel() }
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

    #if canImport(ImagePlayground)
      if request.mode == .image {
        progress(.init(status: "Pending", progress: 5, message: "Generating local image"))
        let generatedImage = try await createImage(
          creator: creator,
          concepts: [.text(lockedPrompt)],
          style: style
        )
        let image = try fittedImage(
          generatedImage,
          width: dimensions.width,
          height: dimensions.height
        )
        let resultURL = outputDirectory.appendingPathComponent("result.png")
        if FileManager.default.fileExists(atPath: resultURL.path) {
          try FileManager.default.removeItem(at: resultURL)
        }
        try writePNG(image, to: resultURL)
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

      progress(
        .init(
          status: "Pending",
          progress: 5,
          message: "Generating the first continuity anchor"
        )
      )
      #if canImport(AppKit)
        await MainActor.run {
          NSApplication.shared.activate(ignoringOtherApps: true)
          for window in NSApplication.shared.windows {
            window.orderFrontRegardless()
          }
        }
        // Give AppKit time to commit foreground activation before Image Playground
        // performs its stricter foreground-only check.
        try await Task.sleep(nanoseconds: 1_500_000_000)
      #endif
      let generatedMasterFrame = try await createAnimationMasterFrame(
        creator: creator,
        lockedPrompt: lockedPrompt,
        originalPrompt: request.prompt,
        frameCount: request.frameCount,
        referencePath: request.referenceImagePath,
        style: style,
        progress: progress
      )
      let masterFrame = try fittedImage(
        generatedMasterFrame,
        width: dimensions.width,
        height: dimensions.height
      )
      let anchorCount = AnimationAnchorPlan.anchorCount(
        forFrameCount: request.frameCount
      )
      var compositeKeyframes = [masterFrame]
      if anchorCount > 1 {
        for anchorIndex in 1..<anchorCount {
          try Task.checkCancellation()
          progress(
            .init(
              status: "Pending",
              progress: 12 + (Double(anchorIndex - 1) / Double(anchorCount - 1)) * 16,
              message: "Generating continuity anchor \(anchorIndex + 1) of \(anchorCount)"
            )
          )
          do {
            let anchor = try await createAnimationAnchorFrame(
              originalPrompt: request.prompt,
              lockedPrompt: lockedPrompt,
              masterFrame: masterFrame,
              previousAnchor: compositeKeyframes[compositeKeyframes.count - 1],
              anchorIndex: anchorIndex,
              anchorCount: anchorCount,
              style: style,
              width: dimensions.width,
              height: dimensions.height
            )
            compositeKeyframes.append(anchor)
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            throw LocalGenerationError.imageCreationFailed(
              frame: anchorIndex + 1,
              frameCount: anchorCount,
              attempts: 2,
              retriedWithoutReference: false,
              reason: animationFailureReason(
                error,
                unit: "animation anchor"
              )
            )
          }
        }
      }
    #else
      throw LocalGenerationError.unavailable
    #endif

    var frameURLs = [URL]()
    var previousFrame = masterFrame
    for frameIndex in 0..<request.frameCount {
      try Task.checkCancellation()
      progress(
        .init(
          status: "Pending",
          progress: 30 + (Double(frameIndex) / Double(request.frameCount)) * 63,
          message: "Completing referenced frame \(frameIndex + 1) of \(request.frameCount)"
        )
      )
      let image: CGImage
      let sample = AnimationTimelineSample.at(
        frameIndex: frameIndex,
        frameCount: request.frameCount,
        keyframeCount: compositeKeyframes.count
      )
      if sample.isKeyframe {
        image = compositeKeyframes[sample.beforeIndex]
      } else {
        do {
          image = try await createCompositeAnimationFrame(
            originalPrompt: request.prompt,
            keyframes: compositeKeyframes,
            sample: sample,
            previousFrame: previousFrame,
            style: style,
            width: dimensions.width,
            height: dimensions.height
          )
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          throw LocalGenerationError.imageCreationFailed(
            frame: frameIndex + 1,
            frameCount: request.frameCount,
            attempts: 2,
            retriedWithoutReference: false,
            reason: animationFailureReason(
              error,
              unit: "animation frame"
            )
          )
        }
      }
      previousFrame = image
      let frameURL = outputDirectory.appendingPathComponent(
        String(format: "frame-%04d.png", frameIndex)
      )
      try writePNG(image, to: frameURL)
      frameURLs.append(frameURL)
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
    #if canImport(UIKit)
      private func waitForForegroundApplication() async -> Bool {
        for _ in 0..<40 {
          if await MainActor.run(body: { UIApplication.shared.applicationState == .active }) {
            return true
          }
          try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
      }
    #endif

    @available(iOS 18.4, macOS 15.4, *)
    private func imageConcept(at url: URL) -> ImagePlaygroundConcept? {
      ImagePlaygroundConcept.image(url)
    }

    @available(iOS 18.4, macOS 15.4, *)
    private func createImage(
      creator: ImageCreator,
      concepts: [ImagePlaygroundConcept],
      style: ImagePlaygroundStyle
    ) async throws -> CGImage {
      guard
        let generatedImage = try await createImages(
          creator: creator,
          concepts: concepts,
          style: style,
          limit: 1
        ).first
      else {
        throw LocalGenerationError.noImageReturned
      }
      return generatedImage
    }

    @available(iOS 18.4, macOS 15.4, *)
    private func createImages(
      creator: ImageCreator,
      concepts: [ImagePlaygroundConcept],
      style: ImagePlaygroundStyle,
      limit: Int
    ) async throws -> [CGImage] {
      var generatedImages = [CGImage]()
      if #available(iOS 26.4, macOS 26.4, *) {
        var options = ImagePlaygroundOptions()
        options.creationVariety = .low
        options.personalization = .disabled
        let images = creator.images(
          for: concepts,
          style: style,
          options: options,
          limit: limit
        )
        for try await result in images {
          try Task.checkCancellation()
          generatedImages.append(result.cgImage)
        }
      } else {
        let images = creator.images(for: concepts, style: style, limit: limit)
        for try await result in images {
          try Task.checkCancellation()
          generatedImages.append(result.cgImage)
        }
      }
      guard !generatedImages.isEmpty else { throw LocalGenerationError.noImageReturned }
      return generatedImages
    }

    @available(iOS 18.4, macOS 15.4, *)
    private func createAnimationAnchorFrame(
      originalPrompt: String,
      lockedPrompt: String,
      masterFrame: CGImage,
      previousAnchor: CGImage,
      anchorIndex: Int,
      anchorCount: Int,
      style: ImagePlaygroundStyle,
      width: Int,
      height: Int
    ) async throws -> CGImage {
      let fraction = Double(anchorIndex) / Double(max(1, anchorCount - 1))
      let board = try CompositeAnimationRenderer.continuityBoard(
        before: masterFrame,
        after: previousAnchor,
        previous: previousAnchor
      )
      do {
        let candidates = try await createImages(
          creator: try await ImageCreator(),
          concepts: [
            .text(
              CompositeAnimationPromptPlan.anchorOnlyPrompt(
                lockedPrompt: lockedPrompt,
                originalPrompt: AnimationPromptPlan.originalPromptFallback(
                  for: originalPrompt
                ),
                fraction: fraction
              )
            ),
            .image(board),
          ],
          style: style,
          limit: 3
        )
        let fittedCandidates =
          try candidates
          .filter { !AnimationFrameConsistency.looksLikeContinuityBoard($0) }
          .map { try fittedImage($0, width: width, height: height) }
        if let bestCandidate = AnimationFrameConsistency.bestCandidate(
          from: fittedCandidates,
          previous: previousAnchor,
          before: masterFrame,
          after: previousAnchor
        ) {
          return bestCandidate
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // Literal cell completion is the second reference-preserving attempt.
      }

      let completedBoard = try await createImage(
        creator: try await ImageCreator(),
        concepts: [
          .text(
            CompositeAnimationPromptPlan.completedAnchorBoardPrompt(
              fraction: fraction
            )
          ),
          .image(board),
        ],
        style: style
      )
      if AnimationFrameConsistency.looksLikeContinuityBoard(completedBoard) {
        let target = try CompositeAnimationRenderer.targetCell(from: completedBoard)
        return try fittedImage(target, width: width, height: height)
      }
      return try fittedImage(completedBoard, width: width, height: height)
    }

    @available(iOS 18.4, macOS 15.4, *)
    private func createCompositeAnimationFrame(
      originalPrompt: String,
      keyframes: [CGImage],
      sample: AnimationTimelineSample,
      previousFrame: CGImage,
      style: ImagePlaygroundStyle,
      width: Int,
      height: Int
    ) async throws -> CGImage {
      let before = keyframes[sample.beforeIndex]
      let after = keyframes[sample.afterIndex]

      let board = try CompositeAnimationRenderer.continuityBoard(
        before: before,
        after: after,
        previous: previousFrame
      )
      do {
        let candidates = try await createImages(
          creator: try await ImageCreator(),
          concepts: [
            .text(
              CompositeAnimationPromptPlan.targetOnlyPrompt(
                originalPrompt: AnimationPromptPlan.originalPromptFallback(
                  for: originalPrompt
                ),
                fraction: sample.fraction
              )
            ),
            .image(board),
          ],
          style: style,
          limit: 3
        )
        let fittedCandidates =
          try candidates
          .filter { !AnimationFrameConsistency.looksLikeContinuityBoard($0) }
          .map { try fittedImage($0, width: width, height: height) }
        if let bestCandidate = AnimationFrameConsistency.bestCandidate(
          from: fittedCandidates,
          previous: previousFrame,
          before: before,
          after: after
        ) {
          return bestCandidate
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // Literal cell completion is the second reference-preserving attempt.
      }

      let completedBoard = try await createImage(
        creator: try await ImageCreator(),
        concepts: [
          .text(
            CompositeAnimationPromptPlan.completedBoardPrompt(
              fraction: sample.fraction
            )
          ),
          .image(board),
        ],
        style: style
      )
      if AnimationFrameConsistency.looksLikeContinuityBoard(completedBoard) {
        let target = try CompositeAnimationRenderer.targetCell(from: completedBoard)
        return try fittedImage(target, width: width, height: height)
      }
      return try fittedImage(completedBoard, width: width, height: height)
    }

    private func animationFailureReason(_ error: Error, unit: String) -> String {
      let detail = error.localizedDescription.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      let suffix = detail.isEmpty ? "" : " Last local error: \(detail)"
      return
        "Apple returned no usable standalone \(unit) after ranked candidate selection and reference-board recovery.\(suffix)"
    }

    @available(iOS 18.4, macOS 15.4, *)
    private func createAnimationMasterFrame(
      creator: ImageCreator,
      lockedPrompt: String,
      originalPrompt: String,
      frameCount: Int,
      referencePath: String?,
      style: ImagePlaygroundStyle,
      progress: @escaping @Sendable (LocalGenerationProgress) -> Void
    ) async throws -> CGImage {
      let reference = referencePath.flatMap {
        imageConcept(at: URL(fileURLWithPath: $0))
      }
      let attempts = AnimationPromptPlan.attempts(
        lockedPrompt: lockedPrompt,
        originalPrompt: originalPrompt,
        hasReference: reference != nil
      )
      var lastReason = "Apple reported an unspecified image-creation failure."
      var retriedWithoutReference = false
      var completedAttempts = 0
      for (attemptIndex, attempt) in attempts.enumerated() {
        try Task.checkCancellation()
        if attemptIndex > 0 {
          retriedWithoutReference =
            retriedWithoutReference || (reference != nil && !attempt.includeReference)
          progress(
            .init(
              status: "Pending",
              progress: 25 + Double(attemptIndex) * 2,
              message:
                "Retrying cohesive master artwork (attempt \(attemptIndex + 1) of \(attempts.count))"
            )
          )
          try await Task.sleep(nanoseconds: 500_000_000)
        }
        var concepts = [ImagePlaygroundConcept.text(attempt.prompt)]
        if attempt.includeReference, let reference {
          concepts.append(reference)
        }
        do {
          let attemptCreator = attemptIndex == 0 ? creator : try await ImageCreator()
          completedAttempts += 1
          return try await createImage(
            creator: attemptCreator,
            concepts: concepts,
            style: attempt.useFallbackStyle ? .illustration : style
          )
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          lastReason = imageCreationReason(error)
          if let creatorError = error as? ImageCreator.Error,
            case .backgroundCreationForbidden = creatorError
          {
            break
          }
        }
      }
      throw LocalGenerationError.imageCreationFailed(
        frame: 1,
        frameCount: frameCount,
        attempts: completedAttempts,
        retriedWithoutReference: retriedWithoutReference,
        reason: lastReason
      )
    }

    @available(iOS 18.4, macOS 15.4, *)
    private func imageCreationReason(_ error: Swift.Error) -> String {
      guard let creatorError = error as? ImageCreator.Error else {
        return error.localizedDescription
      }
      switch creatorError {
      case .notSupported: return "Image Playground is not supported on this device."
      case .unavailable: return "Image Playground is temporarily unavailable."
      case .creationCancelled: return "Apple cancelled image creation."
      case .faceInImageTooSmall:
        return "The face in the reference image is too small for Image Playground."
      case .unsupportedLanguage:
        return "Image Playground does not support the prompt language."
      case .unsupportedInputImage:
        return "Image Playground rejected the reference image."
      case .backgroundCreationForbidden:
        return "Keep Clawnsole open in the foreground while frames are generated."
      case .creationFailed:
        return
          "Apple still reported an image-creation failure after the recovery attempts. "
          + "Try a shorter prompt or fewer frames."
      case .conceptsRequirePersonIdentity:
        return "The prompt requires a person identity that Image Playground could not resolve."
      @unknown default: return error.localizedDescription
      }
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
                You are a production animation art director. Turn requests into a compact visual continuity specification. Lock characters, wardrobe, palette, line style, setting, lighting, camera, and gradual action. Never conflict with the request. Stay under 36 words and output only the reusable image prompt.
                """
            )
            let response = try await session.respond(
              to:
                "Expand and continuity-lock this request for \(request.frameCount) frame(s): \(request.prompt)"
            )
            if let content = AnimationPromptPlan.validatedExpandedLock(response.content) {
              return content
            }
          } catch {
            // The deterministic lock remains usable when Apple Intelligence is busy.
          }
        }
      }
    #endif
    return fallback
  }
}
