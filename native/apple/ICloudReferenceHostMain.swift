import Foundation
import Darwin

/// Private JSON-lines transport for the Dart companion. URLs and source paths
/// stay in the pipe and journal, never command arguments or diagnostic logs.
@main
struct ICloudReferenceHostMain {
  static func main() {
    let arguments = CommandLine.arguments
    guard arguments.count == 3, arguments[1] == "--journal-dir",
      arguments[2].hasPrefix("/")
    else {
      FileHandle.standardError.write(Data("Expected --journal-dir with an absolute private directory.\n".utf8))
      exit(64)
    }
    let journalDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true).standardizedFileURL
    let journalLock: JournalProcessLock
    do {
      journalLock = try JournalProcessLock(directory: journalDirectory)
    } catch {
      // Never log the private path or an OS error carrying it. A second helper
      // must not recover a journal while its predecessor is still publishing.
      FileHandle.standardError.write(Data("The private iCloud hosting journal is unavailable or already in use.\n".utf8))
      exit(75)
    }
    defer { journalLock.release() }
    let service = ICloudReferenceHosting(
      configuration: .userDrive,
      journalDirectory: journalDirectory
    )
    let output = ProtocolOutput()
    let requests = DispatchGroup()
    var input = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      // FileHandle.read(upToCount:) may fill its requested buffer before
      // returning on a pipe. POSIX read returns the available bytes immediately,
      // so a persistent companion can receive a reply without closing stdin.
      let count = buffer.withUnsafeMutableBytes {
        Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count)
      }
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        FileHandle.standardError.write(Data("Could not read iCloud hosting request.\n".utf8))
        exit(74)
      }
      input.append(contentsOf: buffer.prefix(count))
      while let newline = input.firstIndex(of: 10) {
        let line = Data(input[..<newline])
        input.removeSubrange(...newline)
        guard line.count <= 65_536,
          let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let id = object["id"] as? String, !id.isEmpty, id.count <= 128,
          let method = object["method"] as? String,
          let methodArguments = object["arguments"] as? [String: Any]
        else {
          output.write(["id": NSNull(), "error": ["code": "invalid", "message": "Invalid iCloud hosting request."]])
          continue
        }
        requests.enter()
        Task.detached {
          let result = await service.handle(method: method, arguments: methodArguments)
          output.write(["id": id, "result": result])
          requests.leave()
        }
      }
      if input.count > 65_536 {
        output.write(["id": NSNull(), "error": ["code": "invalid", "message": "iCloud hosting request is too large."]])
        exit(65)
      }
    }
    if !input.isEmpty {
      output.write(["id": NSNull(), "error": ["code": "invalid", "message": "Incomplete iCloud hosting request."]])
      exit(65)
    }
    // EOF also occurs when the companion crashes. Never let an orphaned
    // Foundation call hold the journal lock forever after its parent is gone.
    // Intent was persisted before publication, so an interrupted call recovers
    // as uncertain and must be cleaned up rather than published a second time.
    if requests.wait(timeout: .now() + 5) == .timedOut { exit(75) }
  }
}

private final class ProtocolOutput: @unchecked Sendable {
  private let lock = NSLock()

  func write(_ response: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) else {
      return
    }
    data.append(10)
    lock.lock()
    defer { lock.unlock() }
    FileHandle.standardOutput.write(data)
  }
}

/// This lock survives stdin EOF while in-flight work drains. The kernel releases
/// it on crash/SIGKILL. Keep the lockfile: unlinking a locked inode would let a
/// successor create a different inode and acquire a second independent lock.
private final class JournalProcessLock {
  private var descriptor: Int32 = -1

  init(directory: URL) throws {
    let fm = FileManager.default
    var information = stat()
    if lstat(directory.path, &information) != 0 {
      guard errno == ENOENT else { throw LockFailure.unavailable }
      try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                             attributes: [.posixPermissions: 0o700])
    }
    let directoryFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard directoryFD >= 0 else { throw LockFailure.unavailable }
    defer { Darwin.close(directoryFD) }
    guard fstat(directoryFD, &information) == 0,
          information.st_mode & S_IFMT == S_IFDIR,
          information.st_uid == geteuid(),
          fchmod(directoryFD, 0o700) == 0 else { throw LockFailure.unavailable }
    let fd = openat(directoryFD, ".host.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw LockFailure.unavailable }
    var locked = false
    defer { if !locked { Darwin.close(fd) } }
    guard fstat(fd, &information) == 0,
          information.st_mode & S_IFMT == S_IFREG,
          information.st_uid == geteuid(), information.st_nlink == 1,
          fchmod(fd, 0o600) == 0,
          flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw LockFailure.unavailable }
    descriptor = fd
    locked = true
  }

  func release() {
    if descriptor >= 0 {
      flock(descriptor, LOCK_UN)
      Darwin.close(descriptor)
      descriptor = -1
    }
  }

  deinit { release() }
  private enum LockFailure: Error { case unavailable }
}
