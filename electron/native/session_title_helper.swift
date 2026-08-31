import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

private let maximumInputBytes = 16_384
private let maximumOutputBytes = 4_096
private let maximumSourceCharacters = 2_048
private let maximumNameCharacters = 128

private struct SessionNameRequest: Decodable {
  let source: String
}

private struct SessionNameResponse: Encodable {
  let name: String?

  private enum CodingKeys: String, CodingKey {
    case name
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
  }
}

@main
private enum SessionTitleHelper {
  static func main() async {
    let name = await generateFromStandardInput()
    writeResponse(SessionNameResponse(name: name))
  }

  private static func generateFromStandardInput() async -> String? {
    do {
      let input = try readBoundedStandardInput()
      guard !input.isEmpty, input.count <= maximumInputBytes else { return nil }
      let request = try JSONDecoder().decode(SessionNameRequest.self, from: input)
      let source = String(
        request.source
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .prefix(maximumSourceCharacters)
      )
      guard !source.isEmpty else { return nil }

      #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return await generateName(for: source)
      }
      #endif
      return nil
    } catch {
      return nil
    }
  }

  private static func readBoundedStandardInput() throws -> Data {
    var input = Data()
    while input.count <= maximumInputBytes {
      let remaining = maximumInputBytes + 1 - input.count
      let chunk = try FileHandle.standardInput.read(
        upToCount: min(4_096, remaining)
      ) ?? Data()
      if chunk.isEmpty { break }
      input.append(chunk)
    }
    return input
  }

  #if canImport(FoundationModels)
  @available(macOS 26.0, *)
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
      return name.isEmpty ? nil : String(name.prefix(maximumNameCharacters))
    } catch {
      return nil
    }
  }
  #endif

  private static func writeResponse(_ response: SessionNameResponse) {
    var encoded = (try? JSONEncoder().encode(response)) ?? Data("{\"name\":null}".utf8)
    if encoded.count + 1 > maximumOutputBytes {
      encoded = Data("{\"name\":null}".utf8)
    }
    encoded.append(0x0A)
    FileHandle.standardOutput.write(encoded)
  }
}
