import ClawnsoleAppleLocal
import Flutter
import Foundation

private actor AppleLocalJobManager {
  private var jobs = [String: LocalGenerationProgress]()

  func start(arguments: [String: Any]) throws -> String {
    let jobId =
      (arguments["requestId"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ) ?? UUID().uuidString
    guard !jobId.isEmpty else {
      throw LocalGenerationError.invalidRequest("A request id is required.")
    }
    let fileManager = FileManager.default
    let support = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("Clawnsole/AppleLocal", isDirectory: true)
    let output = support.appendingPathComponent("jobs/\(jobId)", isDirectory: true)
    let models = support.appendingPathComponent("models", isDirectory: true)
    var payload = arguments
    payload["requestId"] = jobId
    payload["outputDirectory"] = output.path
    payload["modelsDirectory"] = models.path
    let data = try JSONSerialization.data(withJSONObject: payload)
    let request = try JSONDecoder().decode(LocalGenerationRequest.self, from: data)
    try request.validate()
    jobs[jobId] = LocalGenerationProgress(
      status: "Pending",
      progress: 0,
      message: "Queued on this device"
    )
    Task {
      do {
        _ = try await LocalGenerationEngine().generate(request) { update in
          Task { await self.record(update, for: jobId) }
        }
      } catch {
        await Task.yield()
        let previousProgress = jobs[jobId]?.progress ?? 0
        let failureProgress = max(
          previousProgress,
          (error as? LocalGenerationError)?.failureProgress ?? 0
        )
        record(
          LocalGenerationProgress(
            status: "Error",
            progress: failureProgress,
            message: "Apple Local animation stopped",
            error: error.localizedDescription
          ),
          for: jobId
        )
      }
    }
    return jobId
  }

  func progress(for jobId: String) -> LocalGenerationProgress? {
    jobs[jobId]
  }

  private func record(_ progress: LocalGenerationProgress, for jobId: String) {
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
            let available = await LocalGenerationEngine.isAvailable()
            await MainActor.run { result(available) }
          }
        #endif
      case "submit":
        guard let arguments = call.arguments as? [String: Any] else {
          return result(
            FlutterError(
              code: "invalid_request",
              message: "Apple Local needs a request object.",
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
              message: "Apple Local needs a job id.",
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
