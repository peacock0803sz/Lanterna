import DuckDB
import Foundation

// MARK: - LogRotation

/// How often a launch starts a sibling file inside its run.
/// The launch boundary always starts a new file regardless.
enum LogRotation: Hashable, Equatable, Sendable {
  case hourly
  case daily
  case weekly

  // MARK: Lifecycle

  /// Reads one config word. Unknown words read as nil, so callers
  /// fall back to the default.
  init?(configWord: String) {
    switch configWord {
    case "hourly": self = .hourly
    case "daily": self = .daily
    case "weekly": self = .weekly
    default: return nil
    }
  }

  // MARK: Internal

  /// The words the settings and the config file use, in menu order.
  /// Absent in the file means daily.
  static let offered: [LogRotation] = [.hourly, .daily, .weekly]

  /// The config words in the same order, for validation.
  static let offeredWords = ["hourly", "daily", "weekly"]

  /// The word the config file holds for this choice.
  var configWord: String {
    switch self {
    case .hourly: "hourly"
    case .daily: "daily"
    case .weekly: "weekly"
    }
  }

  /// The menu name for this choice.
  var menuName: String {
    switch self {
    case .hourly: "Hourly"
    case .daily: "Daily"
    case .weekly: "Weekly"
    }
  }

  /// Which period one instant falls in. Two instants sharing a
  /// bucket share a file.
  func bucket(milliseconds: Int64) -> Int64 {
    milliseconds / periodMilliseconds
  }

  // MARK: Private

  private var periodMilliseconds: Int64 {
    switch self {
    case .hourly: 3_600_000
    case .daily: 86_400_000
    case .weekly: 604_800_000
    }
  }
}

// MARK: - LogLaunchStore

/// Holds the writable store for one launch. Opens lazily on the
/// first spill and starts a numbered sibling whenever the clock
/// crosses into a new rotation period.
// swiftlint:disable:next no_unchecked_sendable - Every mutable state below is guarded by the lock; the database itself is Sendable
final class LogLaunchStore: @unchecked Sendable {

  // MARK: Lifecycle

  init(
    directory: URL,
    launchID: String,
    origin: LogPersistence.Origin,
    buildVersion: String,
    startedAtMilliseconds: Int64,
    rotation: LogRotation,
    clock: @escaping () -> Int64 = { Int64(Foundation.Date().timeIntervalSince1970 * 1000) }
  ) {
    self.directory = directory
    self.launchID = launchID
    self.origin = origin
    self.buildVersion = buildVersion
    self.startedAtMilliseconds = startedAtMilliseconds
    self.rotation = rotation
    self.clock = clock
  }

  // MARK: Internal

  /// The store to write through, opening it on first use. Reads
  /// never touch this path, so opening stays a spill-side cost.
  func database() throws -> Database {
    lock.lock()
    defer { lock.unlock() }
    let bucket = rotation.bucket(milliseconds: clock())
    if cached == nil {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      currentBucket = bucket
    } else if bucket != currentBucket {
      currentBucket = bucket
      currentPart += 1
      cached = nil
    }
    if cached == nil {
      let url = LogPersistence.fileURL(in: directory, launchID: launchID, part: currentPart)
      cached = try LogPersistence.openStore(
        at: url,
        launchID: launchID,
        origin: origin,
        buildVersion: buildVersion,
        startedAtMilliseconds: startedAtMilliseconds
      )
    }
    return cached!
  }

  /// The store already open at `url`, if this launch is writing
  /// there. Never opens one, so a read cannot create a file.
  func openDatabase(at url: URL) -> Database? {
    lock.lock()
    defer { lock.unlock() }
    guard let cached else {
      return nil
    }
    let current = LogPersistence.fileURL(in: directory, launchID: launchID, part: currentPart)
    return current.standardizedFileURL == url.standardizedFileURL ? cached : nil
  }

  /// Releases the open store. The next write opens a fresh one.
  func close() {
    lock.lock()
    defer { lock.unlock() }
    cached = nil
  }

  /// Takes a new rotation for the rest of the run. The next write
  /// splits under the new period; open files stay where they are.
  func update(rotation: LogRotation) {
    lock.lock()
    defer { lock.unlock() }
    self.rotation = rotation
  }

  // MARK: Private

  private let lock = NSLock()
  private let directory: URL
  private let launchID: String
  private let origin: LogPersistence.Origin
  private let buildVersion: String
  private let startedAtMilliseconds: Int64
  private var rotation: LogRotation
  private let clock: () -> Int64
  private var cached: Database?
  private var currentBucket: Int64 = 0
  private var currentPart = 0

}
