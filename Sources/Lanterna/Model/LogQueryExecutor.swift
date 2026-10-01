import DuckDB
import Foundation

// MARK: - SkippedStoreFile

/// One store file left out of the results, with why.
struct SkippedStoreFile: Equatable, Sendable {
  var url: URL
  var reason: String
}

// MARK: - ExecutedLogQuery

/// What one run returns: merged rows plus the files skipped.
struct ExecutedLogQuery: Equatable, Sendable {
  var rows: [DiagnosticRow]
  var skipped: [SkippedStoreFile]
  var skippedLines: Int
}

// MARK: - LogQueryExecutor

/// Runs read queries across one origin's store files.
///
/// Each run lets the store write its answer to a temporary
/// comma-separated file and parses that back. The statement still
/// does the filtering, ordering, and capping; only the last
/// transport step goes through text.
final class LogQueryExecutor: Sendable {

  // MARK: Lifecycle

  /// - Parameter files: the store files to read, oldest first.
  /// - Parameter liveStore: the store this process holds open for
  ///   writing at one of those files, if any. Required, so a caller
  ///   cannot forget it and open the live file a second time.
  init(files: [URL], liveStore: @escaping @Sendable (URL) -> Database?) {
    self.files = files
    self.liveStore = liveStore
  }

  // MARK: Internal

  /// The database refused the statement itself, on a file whose shape
  /// already checked out, so every other file would refuse it too. The
  /// run fails with this rather than returning no rows beside a skip
  /// per file.
  struct StatementError: Error, CustomStringConvertible {
    var underlying: any Error

    var description: String {
      if
        case DatabaseError.preparedStatementFailedToInitialize(let reason) = underlying,
        let reason
      {
        return reason
      }
      return String(describing: underlying)
    }
  }

  /// Runs a lightweight predicate over every file and merges the
  /// rows by time and order, keeping the newest `limit` of them.
  /// Unreadable files are skipped with their reason kept; only a
  /// statement the database refuses fails the whole run.
  func run(
    predicate: String,
    values: [SQLLiteral],
    limit: Int = 5000,
    progress: @escaping (Double) -> Void = { _ in }
  ) throws -> ExecutedLogQuery {
    let whereClause = try inline(values, into: predicate)
    return try fetch(
      sql: "SELECT seq, ts_ms, level, category, message, launch_id, build_version, payload "
        + "FROM entries WHERE \(whereClause) ORDER BY ts_ms DESC, seq DESC LIMIT \(limit)",
      limit: limit,
      progress: progress
    )
  }

  /// Runs a checked database statement. The statement must yield
  /// the entry columns under their stored names, since the wrapper
  /// picks them by name. The wrapper keeps the merged order across
  /// files and the newest rows up to the statement's own `LIMIT`,
  /// or up to `defaultCap` when it has none.
  func runStatement(
    _ sql: String,
    defaultCap: Int = 5000,
    progress: @escaping (Double) -> Void = { _ in }
  ) throws -> ExecutedLogQuery {
    let cap = rowCap(in: sql, default: defaultCap)
    return try fetch(
      sql: "SELECT seq, ts_ms, level, category, message, launch_id, build_version, payload "
        + "FROM (\n\(sql)\n) ORDER BY ts_ms DESC, seq DESC LIMIT \(cap)",
      limit: cap,
      progress: progress
    )
  }

  /// Fills `?` markers with quoted values. The count must match;
  /// a mismatch means the translator and the predicate drifted.
  func inline(_ values: [SQLLiteral], into predicate: String) throws -> String {
    enum InlineError: Error { case markerMismatch }
    var out = ""
    var remaining = values[...]
    var quote: Character?
    var index = predicate.startIndex
    while index < predicate.endIndex {
      let character = predicate[index]
      if let open = quote {
        out.append(character)
        if character == open {
          let next = predicate.index(after: index)
          if next < predicate.endIndex, predicate[next] == open {
            out.append(open)
            index = predicate.index(after: next)
            continue
          }
          quote = nil
        }
      } else if character == "'" {
        quote = character
        out.append(character)
      } else if character == "?" {
        guard let first = remaining.first else {
          throw InlineError.markerMismatch
        }
        remaining = remaining.dropFirst()
        switch first {
        case .text(let text): out += LogPersistence.literal(text)
        case .integer(let number): out += String(number)
        case .real(let number): out += String(number)
        }
      } else {
        out.append(character)
      }
      index = predicate.index(after: index)
    }
    guard remaining.isEmpty else {
      throw InlineError.markerMismatch
    }
    return out
  }

  // MARK: Private

  private struct MissingStoreFile: Error, CustomStringConvertible {
    var description: String {
      "file does not exist"
    }
  }

  private let files: [URL]
  private let liveStore: @Sendable (URL) -> Database?

  private func fetch(sql: String, limit: Int, progress: (Double) -> Void) throws -> ExecutedLogQuery {
    var rows = [DiagnosticRow]()
    var skipped = [SkippedStoreFile]()
    var skippedLines = 0
    for (index, file) in files.enumerated() {
      try Task.checkCancellation()
      do {
        let found = try read(file: file, sql: sql)
        rows.append(contentsOf: found.rows)
        skippedLines += found.skippedLines
      } catch let error as StatementError {
        throw error
      } catch {
        skipped.append(SkippedStoreFile(url: file, reason: String(describing: error)))
      }
      progress(Double(index + 1) / Double(max(files.count, 1)))
    }
    rows.sort {
      if $0.recordedAtMilliseconds != $1.recordedAtMilliseconds {
        return $0.recordedAtMilliseconds < $1.recordedAtMilliseconds
      }
      return $0.sequence < $1.sequence
    }
    // Each file sent its newest rows, so the cap keeps the newest
    // across files too, matching the trim of the non-persisted store.
    if rows.count > limit {
      rows = Array(rows.suffix(limit))
    }
    return ExecutedLogQuery(rows: rows, skipped: skipped, skippedLines: skippedLines)
  }

  /// The statement's own top-level LIMIT, or the default. A LIMIT
  /// inside a subquery bounds that subquery only.
  private func rowCap(in sql: String, default defaultCap: Int = 5000) -> Int {
    let words = DatabaseStatementCheck.topLevelWords(in: sql)
    var cap = defaultCap
    var cursor = words.startIndex
    while cursor < words.endIndex {
      if words[cursor] == "limit" {
        let next = words.index(after: cursor)
        if next < words.endIndex, let value = Int(words[next]) {
          cap = value
        }
      }
      cursor = words.index(after: cursor)
    }
    return cap
  }

  /// Reads one file without ever writing to it. A file this process
  /// already holds open for writing is read through that same store
  /// inside a read-only transaction, since a second instance on the
  /// file would share the process's lock and drop it on close; any
  /// other file opens in read-only mode. The export runs as a single
  /// prepared statement, which the database refuses to split.
  private func read(file: URL, sql: String) throws -> (rows: [DiagnosticRow], skippedLines: Int) {
    let connection: Connection
    let live = liveStore(file)
    if let live {
      connection = try live.connect()
      try connection.execute("BEGIN TRANSACTION READ ONLY")
    } else {
      guard FileManager.default.fileExists(atPath: file.path) else {
        throw MissingStoreFile()
      }
      let configuration = Database.Configuration()
      try configuration.setValue("READ_ONLY", forKey: "access_mode")
      connection = try Database(store: .file(at: file), configuration: configuration).connect()
    }
    defer {
      if live != nil {
        try? connection.execute("ROLLBACK")
      }
    }
    let stamped = try connection.query(
      "SELECT value FROM meta WHERE key = 'format_version' AND value = '\(LogPersistence.formatVersion)'"
    )
    guard stamped.rowCount > 0 else {
      throw LogPersistence.OpenError.incompatibleShape(found: nil)
    }
    let out = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("csv")
    defer { try? FileManager.default.removeItem(at: out) }
    let export: PreparedStatement
    do {
      export = try PreparedStatement(
        connection: connection,
        query: "COPY (\n\(sql)\n) TO \(LogPersistence.literal(out.path)) (HEADER false)"
      )
    } catch {
      throw StatementError(underlying: error)
    }
    _ = try export.execute()
    let text = try String(contentsOf: out, encoding: .utf8)
    return parseCSV(text)
  }

  private func parseCSV(_ text: String) -> (rows: [DiagnosticRow], skippedLines: Int) {
    var rows = [DiagnosticRow]()
    var skipped = 0
    for fields in csvRecords(in: text) {
      guard
        fields.count == 8,
        let sequence = UInt64(fields[0]),
        let recorded = Int64(fields[1])
      else {
        skipped += 1
        continue
      }
      rows.append(
        DiagnosticRow(
          sequence: sequence,
          recordedAtMilliseconds: recorded,
          level: fields[2],
          category: fields[3].isEmpty ? nil : fields[3],
          message: fields[4],
          launchID: fields[5].isEmpty ? nil : fields[5],
          buildVersion: fields[6].isEmpty ? nil : fields[6],
          payloadJSON: fields[7].isEmpty ? nil : fields[7]
        )
      )
    }
    return (rows, skipped)
  }

  private func csvRecords(in text: String) -> [[String]] {
    var records = [[String]]()
    var fields = [String]()
    var current = ""
    var quoted = false
    var index = text.startIndex
    func endField() {
      fields.append(current)
      current = ""
    }
    while index < text.endIndex {
      let character = text[index]
      if quoted {
        if character == "\"" {
          let next = text.index(after: index)
          if next < text.endIndex, text[next] == "\"" {
            current.append("\"")
            index = next
          } else {
            quoted = false
          }
        } else {
          current.append(character)
        }
      } else if character == "\"" {
        quoted = true
      } else if character == "," {
        endField()
      } else if character == "\n" {
        endField()
        records.append(fields)
        fields = []
      } else if character == "\r" {
        endField()
        records.append(fields)
        fields = []
        let next = text.index(after: index)
        if next < text.endIndex, text[next] == "\n" {
          index = next
        }
      } else {
        current.append(character)
      }
      index = text.index(after: index)
    }
    if !current.isEmpty || !fields.isEmpty {
      endField()
      records.append(fields)
    }
    return records
  }

}
