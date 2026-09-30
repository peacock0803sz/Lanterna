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
}
