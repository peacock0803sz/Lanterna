import Foundation

// MARK: - LaunchLogSink

/// Where a writer's bytes go. A protocol so tests can stand in a sink
/// that fails on cue.
protocol LaunchLogSink: AnyObject {
  func write(_ data: Data) throws
  func close()
}

// MARK: - FileLaunchLogSink

/// An open file, written at its end with no buffering of its own.
final class FileLaunchLogSink: LaunchLogSink {

  // MARK: Lifecycle

  init(url: URL) throws {
    handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
  }

  // MARK: Internal

  func write(_ data: Data) throws {
    try handle.write(contentsOf: data)
  }

  func close() {
    try? handle.close()
  }

  // MARK: Private

  private let handle: FileHandle

}

// MARK: - LaunchLogWriter

/// Appends this launch's lines to its file, one at a time, as they are
/// written.
///
/// Synchronous on purpose: a queue would lose the lines handed over but
/// not yet written when the process is killed. A line is one small write
/// into the page cache, the same kind of cost as the stderr write beside
/// it; nothing is synced to the disk. Never logs anything itself: it runs
/// under the diagnostics store's lock, which does not re-enter. Only ever
/// touched under that lock.
// swiftlint:disable:next no_unchecked_sendable - Only used under DiagnosticLogStore's lock
final class LaunchLogWriter: @unchecked Sendable {

  // MARK: Lifecycle

  /// Opens `url`, which already holds its header. `header` is kept for
  /// making the file again after it has been deleted.
  init(
    url: URL,
    header: String,
    openSink: @escaping (URL) throws -> any LaunchLogSink = { try FileLaunchLogSink(url: $0) }
  ) throws {
    self.url = url
    self.header = header
    self.openSink = openSink
    sink = try openSink(url)
  }

  // MARK: Internal

  let url: URL

  /// Set once a write fails, and from then on for this launch, unless the
  /// file is opened again on purpose.
  private(set) var isStopped = false

  /// Writes one line. False when the line did not reach the file, after
  /// which nothing more is written.
  func append(_ line: String) -> Bool {
    guard !isStopped, let sink else { return false }
    do {
      try sink.write(Data(line.utf8))
      return true
    } catch {
      isStopped = true
      sink.close()
      self.sink = nil
      return false
    }
  }

  func close() {
    sink?.close()
    sink = nil
  }

  /// Opens the same file again, making it with its header first when it
  /// has been deleted meanwhile.
  func reopen() throws {
    close()
    if !FileManager.default.fileExists(atPath: url.path) {
      try Data(header.utf8).write(to: url, options: .withoutOverwriting)
    }
    sink = try openSink(url)
    isStopped = false
  }

  // MARK: Private

  private let header: String
  private let openSink: (URL) throws -> any LaunchLogSink
  private var sink: (any LaunchLogSink)?

}
