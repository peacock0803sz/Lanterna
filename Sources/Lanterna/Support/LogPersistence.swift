import DuckDB
import Foundation

/// Where spilled diagnostic lines live and under which shape.
///
/// One file per launch keeps concurrently running copies from ever
/// writing to each other's store. Rotation splits inside a launch
/// add numbered siblings next to the launch file.
enum LogPersistence {
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
      started_at_ms BIGINT NOT NULL,
      origin VARCHAR NOT NULL,
      build_version VARCHAR NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS entries(
      seq UBIGINT NOT NULL,
      recorded_at_ms BIGINT NOT NULL,
      level VARCHAR NOT NULL,
      category VARCHAR,
      message VARCHAR NOT NULL,
      launch_id VARCHAR NOT NULL,
      build_version VARCHAR NOT NULL,
      payload_json VARCHAR
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
    let name = part == 0 ? "\(launchID).duckdb" : "\(launchID)-part\(part).duckdb"
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
        "INSERT INTO launches(launch_id, started_at_ms, origin, build_version) VALUES ("
          + "\(literal(launchID)), \(startedAtMilliseconds), \(literal(origin.rawValue)), \(literal(buildVersion)))"
      )
      try connection.execute(
        "INSERT INTO meta(key, value) VALUES ('format_version', '\(formatVersion)')"
      )
    }
    return database
  }

  /// Quotes one value for an embedded statement. The store only
  /// ever carries this process's own lines, and quoting the one
  /// delimiter keeps every byte intact.
  static func literal(_ value: String) -> String {
    "'" + value.replacing("\0", with: "").replacing("'", with: "''") + "'"
  }
}
