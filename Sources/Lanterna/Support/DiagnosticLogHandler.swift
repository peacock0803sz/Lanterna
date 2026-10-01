import Foundation
import Logging

// MARK: - DiagnosticLogHandler

/// The one backend this run writes through: stderr and the mirror, as one
/// locked step, so the on-screen log cannot disagree with what was emitted.
/// Takes whatever the logger lets through; the threshold lives on the
/// logger rather than here. Locked around the only mutable state, so
/// sharing it across execution contexts stays sound.
// swiftlint:disable:next no_unchecked_sendable - Every mutable state below is guarded by the lock
final class DiagnosticLogHandler: LogHandler, @unchecked Sendable {

  // MARK: Lifecycle

  init(store: DiagnosticLogStore) {
    self.store = store
  }

  // MARK: Internal

  /// The metadata key a line's category travels under.
  static let categoryKey = "category"
  /// The metadata key a line's context travels under.
  static let contextKey = "context"

  var metadataProvider: Logger.MetadataProvider? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return providerStorage
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      providerStorage = newValue
    }
  }

  /// Takes all it receives. The logger gates ahead of this call, so a
  /// second opinion here would only double the rule.
  var logLevel: Logger.Level {
    get {
      lock.lock()
      defer { lock.unlock() }
      return acceptedLevel
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      acceptedLevel = newValue
    }
  }

  var metadata: Logger.Metadata {
    get {
      lock.lock()
      defer { lock.unlock() }
      return metadataStorage
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      metadataStorage = newValue
    }
  }

  /// The four levels a line is kept at. swift-log's other three fold into
  /// their nearest neighbour.
  static func recordedLevel(_ level: Logger.Level) -> Logger.Level {
    switch level {
    case .trace,
         .debug: .debug
    case .info,
         .notice: .info
    case .warning: .warning
    case .error,
         .critical: .error
    }
  }

  /// `File.swift:123` from a `#fileID` (`Module/File.swift`) and a line.
  static func source(file: String, line: UInt) -> String {
    let name = file.split(separator: "/").last.map(String.init) ?? file
    return "\(name):\(line)"
  }

  /// The typed context back out of the metadata. A `ContextBox` keeps its
  /// value types; anything else that arrives is kept by its description.
  static func context(from value: Logger.Metadata.Value?) -> [String: ContextValue] {
    switch value {
    case .stringConvertible(let convertible as ContextBox):
      convertible.values
    case .dictionary(let dictionary):
      dictionary.mapValues { .string($0.description) }
    case .none:
      [:]
    case .some(let other):
      ["value": .string(other.description)]
    }
  }

  /// A line that arrived without a category (not through `LogLine`) is
  /// filed under the log itself rather than dropped.
  static func category(from value: Logger.Metadata.Value?) -> LogCategory {
    guard case .string(let raw) = value, let category = LogCategory(rawValue: raw) else {
      return .logs
    }
    return category
  }

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(event: LogEvent) {
    let metadata = event.metadata ?? [:]
    store.write(Diagnostics.Record(
      level: Self.recordedLevel(event.level),
      category: Self.category(from: metadata[Self.categoryKey]),
      message: event.message.description,
      source: Self.source(file: event.file, line: event.line),
      context: Self.context(from: metadata[Self.contextKey])
    ))
  }

  // MARK: Private

  private let lock = NSLock()
  private let store: DiagnosticLogStore
  private var metadataStorage: Logger.Metadata = [:]
  private var acceptedLevel = Logger.Level.trace
  private var providerStorage: Logger.MetadataProvider?

}
