import Flutter
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Supplies an optional, on-device semantic refinement for a session name.
///
/// The deterministic Dart name is already durable before this method runs.
/// Every unavailable or failed model call therefore returns null quietly and
/// never interferes with generation submission.
final class SessionNamePlugin {
  private static let maximumSourceCharacters = 2_048

  func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.clawnsole/session_naming",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "generate" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let rawSource = arguments["source"] as? String
      else {
        result(nil)
        return
      }
      let source = String(
        rawSource
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .prefix(Self.maximumSourceCharacters)
      )
      guard !source.isEmpty else {
        result(nil)
        return
      }

      #if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
        Task {
          let generated = await Self.generateName(for: source)
          await MainActor.run { result(generated) }
        }
        return
      }
      #endif
      result(nil)
    }
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, *)
  private static func generateName(for source: String) async -> String? {
    let model = SystemLanguageModel.default
    guard model.isAvailable else { return nil }
    let session = LanguageModelSession(
      model: model,
      instructions: """
        Return one concise project title for the supplied visual-generation prompt.
        Use two to six descriptive words. Return only the title, with no quotes,
        label, punctuation, explanation, or extra line.
        """
    )
    do {
      let response = try await session.respond(
        to: source,
        options: GenerationOptions(
          sampling: .greedy,
          maximumResponseTokens: 12
        )
      )
      let name = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      return name.isEmpty ? nil : String(name.prefix(128))
    } catch {
      return nil
    }
  }
  #endif
}
