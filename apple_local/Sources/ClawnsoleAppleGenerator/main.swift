import ClawnsoleAppleLocal
import Foundation

private final class ProgressWriter: @unchecked Sendable {
  init(fileURL: URL?) {
    self.fileURL = fileURL
    if let fileURL {
      _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
  }

  private let fileURL: URL?
  private let lock = NSLock()

  func emit(_ update: LocalGenerationProgress) {
    guard let data = try? JSONEncoder().encode(update),
      let json = String(data: data, encoding: .utf8)
    else {
      return
    }
    print(json)
    fflush(stdout)
    guard let fileURL, let line = "\(json)\n".data(using: .utf8) else { return }
    lock.lock()
    defer { lock.unlock() }
    guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
    defer { try? handle.close() }
    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: line)
      try handle.synchronize()
    } catch {
      // Stdout remains available for development diagnostics.
    }
  }
}

@main
struct ClawnsoleAppleGenerator {
  static func main() async {
    if CommandLine.arguments.contains("--check-availability") {
      print(await LocalGenerationEngine.isAvailable() ? "true" : "false")
      return
    }
    let arguments = CommandLine.arguments
    let requestFile = argument(named: "--request-file", in: arguments).map {
      URL(fileURLWithPath: $0)
    }
    let progressFile = argument(named: "--progress-file", in: arguments).map {
      URL(fileURLWithPath: $0)
    }
    let writer = ProgressWriter(fileURL: progressFile)
    do {
      let data: Data
      if let requestFile {
        data = try Data(contentsOf: requestFile)
      } else if let line = readLine(), let stdinData = line.data(using: .utf8) {
        data = stdinData
      } else {
        throw LocalGenerationError.invalidRequest("A JSON request is required.")
      }
      let request = try JSONDecoder().decode(LocalGenerationRequest.self, from: data)
      _ = try await LocalGenerationEngine().generate(request) { update in
        writer.emit(update)
      }
    } catch {
      let update = LocalGenerationProgress(
        status: "Error",
        progress: 0,
        message: "Local generation failed",
        error: error.localizedDescription
      )
      writer.emit(update)
      fputs("\(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }

  private static func argument(named name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }
}
