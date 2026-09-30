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
/// The bundled database client exposes no typed reads to library
/// clients, so each run lets the store write its answer to a
/// temporary comma-separated file and parses that back. The
/// statement still does the filtering, counting, and ordering;
/// only the last transport step goes through text.
final class LogQueryExecutor: Sendable {

  // MARK: Lifecycle

  /// The store files to read, oldest first.
  init(files: [URL]) {
    self.files = files
  }

  // MARK: Internal

  /// Runs a lightweight predicate over every file and merges the
  /// rows by time and order. Unreadable files are skipped with
  /// their reason kept, never failing the whole run.
  func run(
    predicate: String,
    values: [SQLLiteral],
    limit: Int = 5000,
    progress: @escaping (Double) -> Void = { _ in }
  ) throws -> ExecutedLogQuery {
    let whereClause = try inline(values, into: predicate)
    return try fetch(
      sql: "SELECT seq, ts_ms, level, category, message, launch_id, build_version, payload "
        + "FROM entries WHERE \(whereClause) ORDER BY ts_ms, seq LIMIT \(limit)",
      limit: limit,
      progress: progress
    )
  }

  /// Runs a checked database statement. The statement must project
  /// the entry columns in store order; the executor wraps it so the
  /// merged order holds across files.
  func runStatement(_ sql: String, progress: @escaping (Double) -> Void = { _ in }) throws -> ExecutedLogQuery {
    try fetch(
      sql: "SELECT seq, ts_ms, level, category, message, launch_id, build_version, payload "
        + "FROM (\(sql)) ORDER BY ts_ms, seq",
      limit: rowCap(in: sql),
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
    if rows.count > limit {
      rows = Array(rows.prefix(limit))
    }
    return ExecutedLogQuery(rows: rows, skipped: skipped, skippedLines: skippedLines)
  }

  private func rowCap(in sql: String, default defaultCap: Int = 5000) -> Int {
    var words = [String]()
    var current = ""
    var quote: Character?
    func flush() {
      if !current.isEmpty {
        words.append(current.lowercased())
        current = ""
      }
    }
    var index = sql.startIndex
    while index < sql.endIndex {
      let character = sql[index]
      if let open = quote {
        if character == open {
          let next = sql.index(after: index)
          if next < sql.endIndex, sql[next] == open {
            index = sql.index(after: next)
            continue
          }
          quote = nil
        }
      } else if character == "'" || character == "\"" || character == "`" {
        quote = character
      } else if character.isLetter || character.isNumber || character == "_" {
        current.append(character)
      } else {
        flush()
      }
      index = sql.index(after: index)
    }
    flush()
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

  private func read(file: URL, sql: String) throws -> (rows: [DiagnosticRow], skippedLines: Int) {
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw MissingStoreFile()
    }
    let database = try Database(store: .file(at: file))
    let connection = try database.connect()
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
    try connection.execute("COPY (\(sql)) TO \(LogPersistence.literal(out.path)) (HEADER false)")
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
