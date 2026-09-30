import DuckDB
import Foundation

// MARK: - LogPersistence

/// Where spilled diagnostic lines live and under which shape.
///
/// One file per launch keeps concurrently running copies from ever
/// writing to each other's store. Rotation splits inside a launch
/// add numbered siblings next to the launch file.
enum LogPersistence {

  // MARK: Internal

  /// Which copy of the app owns a store: the installed build or a
  /// development build. The log window and the cleanup only ever
  /// touch their own origin.
  enum Origin: String {
    case installed = "app"
    case development = "dev"
  }

  /// What opening a store can report. The shape case means the
  /// file belongs to another version and stays untouched.
  enum OpenError: Error, Equatable {
    case incompatibleShape(found: String?)
  }

  /// The stored shape this build reads and writes. A file carrying
  /// any other value is skipped with its count and reason left as
  /// a diagnostic line; old shapes are never migrated.
  static let formatVersion = 1

  /// Tables every store file carries. Entries hold one row per
  /// diagnostic line, launches one row per launch, meta the shape
  /// marker read before anything else.
  static let schemaStatements: [String] = [
    """
    CREATE TABLE IF NOT EXISTS launches(
      launch_id VARCHAR PRIMARY KEY,
      started_at BIGINT NOT NULL,
      origin VARCHAR NOT NULL,
      build_version VARCHAR NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS entries(
      seq UBIGINT NOT NULL,
      ts_ms BIGINT NOT NULL,
      level VARCHAR NOT NULL,
      category VARCHAR,
      message VARCHAR NOT NULL,
      launch_id VARCHAR NOT NULL,
      build_version VARCHAR NOT NULL,
      payload VARCHAR
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS meta(
      key VARCHAR PRIMARY KEY,
      value VARCHAR NOT NULL
    )
    """,
  ]

  /// Picks the origin from where the process runs. A development
  /// build executes out of a build products directory, while the
  /// installed copy runs from its bundle location.
  static func currentOrigin(bundlePath: String = Bundle.main.bundlePath) -> Origin {
    if bundlePath.contains(".build") || bundlePath.contains("DerivedData") {
      return .development
    }
    return .installed
  }

  /// The directory holding one origin's launched files. Created on
  /// first spill, never for a read-only open.
  static func directory(
    applicationSupport: URL,
    origin: Origin
  ) -> URL {
    applicationSupport
      .appendingPathComponent("Lanterna", isDirectory: true)
      .appendingPathComponent("Logs", isDirectory: true)
      .appendingPathComponent(origin.rawValue, isDirectory: true)
  }

  /// The file one launch writes. Rotation inside the launch appends
  /// `-partNNN` siblings beside it.
  static func fileURL(in directory: URL, launchID: String, part: Int = 0) -> URL {
    let name =
      if part == 0 {
        "\(launchID).duckdb"
      } else {
        "\(launchID)\(String(format: "-part%03d", part)).duckdb"
      }
    return directory.appendingPathComponent(name)
  }

  /// Opens a store file for one launch: creates the tables, stamps
  /// the launch row, and confirms the shape marker. Throws the
  /// shape error for files of another version instead of reading
  /// them.
  static func openStore(
    at url: URL,
    launchID: String,
    origin: Origin,
    buildVersion: String,
    startedAtMilliseconds: Int64
  ) throws -> Database {
    let database = try Database(store: .file(at: url))
    try prepare(
      database: database,
      launchID: launchID,
      origin: origin,
      buildVersion: buildVersion,
      startedAtMilliseconds: startedAtMilliseconds
    )
    return database
  }

  /// Opens a store that vanishes with the process. Same tables,
  /// same launch row, no file.
  static func openEphemeral(
    launchID: String,
    origin: Origin,
    buildVersion: String,
    startedAtMilliseconds: Int64
  ) throws -> Database {
    let database = try Database(store: .inMemory)
    try prepare(
      database: database,
      launchID: launchID,
      origin: origin,
      buildVersion: buildVersion,
      startedAtMilliseconds: startedAtMilliseconds
    )
    return database
  }

  /// Quotes one value for an embedded statement. The store only
  /// ever carries this process's own lines, and quoting the one
  /// delimiter keeps every byte intact.
  static func literal(_ value: String) -> String {
    "'" + value.replacing("\0", with: "").replacing("'", with: "''") + "'"
  }

  /// Renders one optional value: quoted text or NULL.
  static func literal(_ value: String?) -> String {
    guard let value else {
      return "NULL"
    }
    return literal(value)
  }

  /// Builds one multi-row INSERT for a flushed batch. Rows missing
  /// their launch or build fall back to the running values, so
  /// every stored line answers where and when it came from.
  static func insertStatement(rows: [DiagnosticRow], launchID: String, buildVersion: String) -> String {
    guard !rows.isEmpty else {
      return "SELECT 1 WHERE 1 = 0"
    }
    let values = rows.map { row in
      "(\(row.sequence), \(row.recordedAtMilliseconds), \(literal(row.level)), "
        + "\(literal(row.category)), \(literal(row.message)), "
        + "\(literal(row.launchID ?? launchID)), \(literal(row.buildVersion ?? buildVersion)), "
        + "\(literal(row.payloadJSON)))"
    }
    return "INSERT INTO entries(seq, ts_ms, level, category, message, "
      + "launch_id, build_version, payload) VALUES " + values.joined(separator: ", ")
  }

  // MARK: Private

  private static func prepare(
    database: Database,
    launchID: String,
    origin: Origin,
    buildVersion: String,
    startedAtMilliseconds: Int64
  ) throws {
    let connection = try database.connect()
    for statement in schemaStatements {
      try connection.execute(statement)
    }
    let stamped = try connection.query(
      "SELECT value FROM meta WHERE key = 'format_version' AND value = '\(formatVersion)'"
    )
    if stamped.rowCount == 0 {
      let metaRows = try connection.query("SELECT key FROM meta")
      if metaRows.rowCount > 0 {
        throw OpenError.incompatibleShape(found: nil)
      }
      try connection.execute(
        "INSERT INTO launches(launch_id, started_at, origin, build_version) VALUES ("
          + "\(literal(launchID)), \(startedAtMilliseconds), \(literal(origin.rawValue)), \(literal(buildVersion)))"
      )
      try connection.execute(
        "INSERT INTO meta(key, value) VALUES ('format_version', '\(formatVersion)')"
      )
    }
  }

}

// MARK: - LogRotation

/// How often a launch starts a sibling file inside its run.
/// The launch boundary always starts a new file regardless.
enum LogRotation: Equatable, Sendable {
  case hourly
  case daily
  case weekly

  /// Which period one instant falls in. Two instants sharing a
  /// bucket share a file.
  func bucket(milliseconds: Int64) -> Int64 {
    milliseconds / periodMilliseconds
  }

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

  /// Releases the open store. The next write opens a fresh one.
  func close() {
    lock.lock()
    defer { lock.unlock() }
    cached = nil
  }

  // MARK: Private

  private let lock = NSLock()
  private let directory: URL
  private let launchID: String
  private let origin: LogPersistence.Origin
  private let buildVersion: String
  private let startedAtMilliseconds: Int64
  private let rotation: LogRotation
  private let clock: () -> Int64
  private var cached: Database?
  private var currentBucket: Int64 = 0
  private var currentPart = 0

}
