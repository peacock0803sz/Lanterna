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
  /// development build. Each keeps its own directory, so the two
  /// never write into each other's files.
  enum Origin: String {
    case installed = "app"
    case development = "dev"
  }

  /// What opening a store can report. The shape case means the
  /// file belongs to another version and stays untouched.
  enum OpenError: Error, Equatable {
    case incompatibleShape(found: String?)
  }

  /// What one origin keeps on disk: how much room its spill files
  /// take, how many launches they cover, and the oldest day among
  /// them. Read for the settings display; removing needs the call
  /// below.
  struct ArchiveStatus: Equatable, Sendable {
    var totalBytes: Int64
    var launchCount: Int
    var oldest: Foundation.Date?
  }

  /// The stored shape this build reads and writes. A file carrying
  /// any other value is refused on open and left out of reads, with
  /// its reason returned beside the results; old shapes are never
  /// migrated.
  static let formatVersion = 1

  /// The retention choices the settings offer, in days. Absent in the
  /// file means thirty days.
  static let offeredRetentionDays = [7, 30, 90]

  /// The disk caps the settings offer, in gigabytes. Absent in the
  /// file means five gigabytes.
  static let offeredDiskLimitsGB = [1, 5, 20]

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

  /// Opens a store file for one launch. A file holding no tables
  /// gets them along with the launch row and the shape marker; a
  /// file already carrying this shape opens as it is. Anything else
  /// throws the shape error before a single table is created.
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

  /// Quotes one value for an embedded statement: stored lines,
  /// filter values, and file paths alike. The quote is doubled and
  /// NUL characters, which statement text cannot carry, are dropped;
  /// every other character survives as is.
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

  /// Keeps the newest rows in store order, dropping the oldest
  /// past the cap. Used for the non-persisted store after each
  /// spill so the in-memory file never grows without bound.
  static func trimStatement(limit: Int = 5000) -> String {
    "DELETE FROM entries WHERE seq NOT IN ("
      + "SELECT seq FROM entries ORDER BY ts_ms DESC, seq DESC LIMIT \(limit))"
  }

  /// Reads what one origin keeps on disk. Missing directories and
  /// unreadable entries read as nothing kept rather than failing.
  static func archiveStatus(in directory: URL) -> ArchiveStatus {
    let files = spillFiles(in: directory)
    var total: Int64 = 0
    var oldest: Foundation.Date?
    var launches = Set<String>()
    for url in files {
      if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
        total += Int64(values.fileSize ?? 0)
        if let modified = values.contentModificationDate {
          if oldest == nil || modified < oldest! {
            oldest = modified
          }
        }
      }
      launches.insert(launchStem(of: url.lastPathComponent))
    }
    return ArchiveStatus(totalBytes: total, launchCount: launches.count, oldest: oldest)
  }

  /// Removes every spill file of one origin. Used by the settings
  /// delete action, which closes the live store before removing and
  /// opens it anew after, so later spills land in a fresh file.
  static func deleteSavedLogs(in directory: URL) throws {
    for url in spillFiles(in: directory) {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// Removes spill files until the retention window and the disk cap
  /// both hold. Files older than the window go first; then the oldest
  /// remaining while usage passes the cap. Launches named in the keep
  /// set are spared, so the running launch never loses its open file.
  /// Returns how many files left. Missing directories mean nothing to do.
  @discardableResult
  static func enforceRetention(
    in directory: URL,
    retentionDays: Int,
    diskLimitBytes: Int64,
    now: Foundation.Date = Foundation.Date(),
    keepingLaunchIDs: Set<String> = []
  ) -> Int {
    let files = spillFiles(in: directory)
    let sheltered = files.filter { keepingLaunchIDs.contains(launchStem(of: $0.lastPathComponent)) }
    var candidates = files.filter { !keepingLaunchIDs.contains(launchStem(of: $0.lastPathComponent)) }
    var removed = 0
    let cutoff = now.addingTimeInterval(TimeInterval(retentionDays * -86400))
    var survivors = [URL]()
    for url in candidates {
      let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      if (modified ?? .distantPast) < cutoff, removeQuietly(url) {
        removed += 1
      } else {
        survivors.append(url)
      }
    }
    candidates = survivors
    var total = (sheltered + candidates).reduce(Int64(0)) { $0 + fileSize(of: $1) }
    for url in candidates {
      guard total > diskLimitBytes else { break }
      let size = fileSize(of: url)
      if removeQuietly(url) {
        removed += 1
        total -= size
      }
    }
    return removed
  }

  /// The spill files of one origin, oldest first. Read-only opens
  /// never create the directory, so a missing one means no files.
  static func spillFiles(in directory: URL) -> [URL] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
      return []
    }
    let urls = names.filter { $0.hasSuffix(".duckdb") }.sorted().map {
      directory.appendingPathComponent($0)
    }
    return urls.sorted { left, right in
      let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      return (leftDate ?? .distantPast) < (rightDate ?? .distantPast)
    }
  }

  // MARK: Private

  /// Removes one file, reporting whether it is gone. A failure
  /// leaves the file for the next pass rather than stopping it.
  private static func removeQuietly(_ url: URL) -> Bool {
    do {
      try FileManager.default.removeItem(at: url)
      return true
    } catch {
      return false
    }
  }

  /// How much room one file takes. Unreadable sizes read as nothing,
  /// so a file that cannot be measured never blocks the cap pass.
  private static func fileSize(of url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
  }

  /// The launch one spill file belongs to: the file stem without
  /// the in-launch rotation suffix.
  private static func launchStem(of fileName: String) -> String {
    var stem = fileName
    if stem.hasSuffix(".duckdb") {
      stem = String(stem.dropLast(".duckdb".count))
    }
    let suffixes = ["-part"]
    for marker in suffixes {
      if let range = stem.range(of: marker, options: .backwards) {
        let tail = stem[range.upperBound...]
        if tail.count == 3, tail.allSatisfy(\.isNumber) {
          return String(stem[..<range.lowerBound])
        }
      }
    }
    return stem
  }

  private static func prepare(
    database: Database,
    launchID: String,
    origin: Origin,
    buildVersion: String,
    startedAtMilliseconds: Int64
  ) throws {
    let connection = try database.connect()
    // Read before anything is created, so a file of another version
    // is refused exactly as it was found.
    let tables = try connection.query("SELECT table_name FROM information_schema.tables")
    if tables.rowCount > 0 {
      var found: String?
      if tables[0].cast(to: String.self).contains("meta") {
        let stamp = try connection.query("SELECT value FROM meta WHERE key = 'format_version'")
        found = stamp.rowCount > 0 ? stamp[0].cast(to: String.self)[0] : nil
      }
      guard found == String(formatVersion) else {
        throw OpenError.incompatibleShape(found: found)
      }
      return
    }
    // One transaction, so a failure part way leaves the file empty
    // and the next open starts over instead of finding tables with
    // no marker and refusing the file for good.
    try connection.execute("BEGIN TRANSACTION")
    do {
      for statement in schemaStatements {
        try connection.execute(statement)
      }
      try connection.execute(
        "INSERT INTO launches(launch_id, started_at, origin, build_version) VALUES ("
          + "\(literal(launchID)), \(startedAtMilliseconds), \(literal(origin.rawValue)), \(literal(buildVersion)))"
      )
      try connection.execute(
        "INSERT INTO meta(key, value) VALUES ('format_version', '\(formatVersion)')"
      )
      try connection.execute("COMMIT")
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

}
