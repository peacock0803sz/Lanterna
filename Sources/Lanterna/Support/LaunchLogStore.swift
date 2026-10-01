import Darwin
import Foundation

// MARK: - LogOrigin

/// Which kind of build wrote a saved log. The installed app and a build
/// from a checkout keep apart, so trying a change never crowds out the
/// launches someone reports from.
enum LogOrigin: String, Sendable {
  case installed
  case development

  // MARK: Internal

  /// Installed when the executable sits inside an `.app` under
  /// `/Applications`, `~/Applications` or the Nix store; anything else
  /// (`swift run`, a scratch bundle, the tests) is a development build.
  static func of(executable: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> LogOrigin {
    let path = executable.standardizedFileURL.path
    guard path.contains(".app/") else { return .development }
    let roots = ["/Applications/", home.standardizedFileURL.path + "/Applications/", "/nix/store/"]
    return roots.contains { path.hasPrefix($0) } ? .installed : .development
  }
}

// MARK: - SavedLaunchFile

/// One launch's file on disk.
struct SavedLaunchFile: Equatable, Sendable {
  let url: URL
  let launch: LaunchID
  let byteCount: Int
}

// MARK: - SavedLaunchRead

/// What reading one file came to.
struct SavedLaunchRead: Sendable {
  let entries: [Diagnostics.LogEntry]
  /// Lines that were not entries: cut short, damaged, or of a kind this
  /// build does not know.
  let skippedLines: Int
  /// False when the header was missing or of another format version, in
  /// which case nothing was read.
  let isReadable: Bool
}

// MARK: - SavedLogsUsage

/// The saved launches in brief, for the settings.
struct SavedLogsUsage: Equatable, Sendable {

  // MARK: Internal

  let byteCount: Int
  let launchCount: Int
  let oldest: Date?

  /// `4.1 MB across 6 launches · oldest Sep 28`, or that there are none.
  func summary(timeZone: TimeZone = .current) -> String {
    guard launchCount > 0 else { return "No saved logs yet." }
    let size = String(format: "%.1f MB", Double(byteCount) / 1_048_576)
    let launches = launchCount == 1 ? "1 launch" : "\(launchCount) launches"
    guard let oldest else { return "\(size) across \(launches)" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.month, .day], from: oldest)
    let month = Self.months[max(0, min(11, (parts.month ?? 1) - 1))]
    return "\(size) across \(launches) · oldest \(month) \(parts.day ?? 1)"
  }

  // MARK: Private

  /// Fixed English month names, so the line reads the same in every locale.
  private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

}

// MARK: - LaunchLogStore

/// Where saved launches live, and making, trimming, deleting and reading
/// them. Every call touches the disk, so none runs on the panel paths:
/// creating and trimming happen at launch, reading in the log window's
/// background work.
struct LaunchLogStore: Sendable {

  // MARK: Lifecycle

  init(directory: URL, timeZone: TimeZone = .current) {
    self.directory = directory
    self.timeZone = timeZone
  }

  // MARK: Internal

  /// The launches kept beside the current one.
  static let launchLimit = 20
  /// The most the kept launches may take together.
  static let byteLimit = 50 * 1024 * 1024

  /// `…/Lanterna/Logs/<origin>`, one folder per origin.
  let directory: URL
  let timeZone: TimeZone

  /// The folder for `origin` under an Application Support directory.
  static func directory(applicationSupport: URL, origin: LogOrigin) -> URL {
    applicationSupport
      .appendingPathComponent("Lanterna", isDirectory: true)
      .appendingPathComponent("Logs", isDirectory: true)
      .appendingPathComponent(origin.rawValue, isDirectory: true)
  }

  /// Makes this launch's file and writes its header. A name already taken
  /// by another launch from the same origin moves to the next `-N`, and
  /// the launch returned carries it.
  func create(for launch: LaunchID, version: String) throws -> (launch: LaunchID, url: URL) {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var candidate = launch
    while true {
      let url = fileURL(for: candidate)
      let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
      if descriptor >= 0 {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try writeHeader(for: candidate, version: version, to: handle)
        try handle.close()
        return (candidate, url)
      }
      guard errno == EEXIST else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      candidate = candidate.nextSuffix(timeZone: timeZone)
    }
  }

  /// Writes a fresh header into an empty file, for a launch whose file is
  /// made again after being deleted.
  func writeHeader(for launch: LaunchID, version: String, to handle: FileHandle) throws {
    let offset = timeZone.secondsFromGMT(for: launch.startedAt)
    try handle.write(contentsOf: Data(LaunchLogCoding.header(launch: launch, version: version, utcOffsetSeconds: offset).utf8))
  }

  func fileURL(for launch: LaunchID) -> URL {
    directory.appendingPathComponent(launch.fileName, isDirectory: false)
  }

  /// Every saved launch, oldest first. Files of any other name are left
  /// alone.
  func files(current: LaunchID? = nil) -> [SavedLaunchFile] {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    return urls.compactMap { url -> SavedLaunchFile? in
      guard var launch = LaunchID.fromFileName(url.lastPathComponent, timeZone: timeZone) else { return nil }
      if launch == current {
        launch = LaunchID(startedAt: launch.startedAt, suffix: launch.suffix, isCurrent: true, timeZone: timeZone)
      }
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      return SavedLaunchFile(url: url, launch: launch, byteCount: size)
    }
    .sorted { $0.launch.fileBaseName < $1.launch.fileBaseName }
  }

  /// Deletes the oldest launches until at most `launchLimit` remain and
  /// together they take at most `byteLimit`. The current launch's file is
  /// never counted or deleted.
  func prune(keeping current: LaunchID) {
    var others = files().filter { $0.launch != current }
    var total = others.reduce(0) { $0 + $1.byteCount }
    while let oldest = others.first, others.count > Self.launchLimit || total > Self.byteLimit {
      try? FileManager.default.removeItem(at: oldest.url)
      total -= oldest.byteCount
      others.removeFirst()
    }
  }

  /// How much the saved launches take, how many there are, and when the
  /// oldest started.
  func usage() -> SavedLogsUsage {
    let files = files()
    return SavedLogsUsage(
      byteCount: files.reduce(0) { $0 + $1.byteCount },
      launchCount: files.count,
      oldest: files.first?.launch.startedAt
    )
  }

  /// Deletes every saved launch but `current`; with nil, every one.
  func deleteAll(except current: LaunchID?) {
    for file in files() where file.launch != current {
      try? FileManager.default.removeItem(at: file.url)
    }
  }

  /// Reads one file. Each line stands alone: a damaged one, including a
  /// last line cut short, is skipped and counted.
  func read(_ file: SavedLaunchFile) -> SavedLaunchRead {
    guard let data = try? Data(contentsOf: file.url) else {
      return SavedLaunchRead(entries: [], skippedLines: 0, isReadable: false)
    }
    var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
    guard let header = lines.first, LaunchLogCoding.isReadableHeader(Data(header)) else {
      return SavedLaunchRead(entries: [], skippedLines: 0, isReadable: false)
    }
    lines.removeFirst()
    var entries = [Diagnostics.LogEntry]()
    entries.reserveCapacity(lines.count)
    var skipped = 0
    for line in lines {
      if let entry = LaunchLogCoding.entry(from: Data(line), launch: file.launch) {
        entries.append(entry)
      } else {
        skipped += 1
      }
    }
    return SavedLaunchRead(entries: entries, skippedLines: skipped, isReadable: true)
  }

}
