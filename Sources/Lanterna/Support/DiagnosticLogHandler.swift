import Foundation
import Logging

// MARK: - DiagnosticLogHandler

/// The one backend this run writes through: stderr and the mirror, as one
/// locked step, so the on-screen log cannot disagree with what was emitted.
/// Takes whatever the logger lets through; the threshold lives on the
/// logger rather than here. A future backend (a file, the system log)
/// arrives as another handler beside this one. Locked around the only
/// mutable state, so sharing it across execution contexts stays sound.
// swiftlint:disable:next no_unchecked_sendable - Every mutable state below is guarded by the lock
final class DiagnosticLogHandler: LogHandler, @unchecked Sendable {

  // MARK: Lifecycle

  init(store: DiagnosticLogStore) {
    self.store = store
  }

  // MARK: Internal

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

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(event: LogEvent) {
    store.write(event.message.description, level: event.level, metadata: event.metadata ?? [:])
  }

  // MARK: Private

  private let lock = NSLock()
  private let store: DiagnosticLogStore
  private var metadataStorage: Logger.Metadata = [:]
  private var acceptedLevel = Logger.Level.trace
  private var providerStorage: Logger.MetadataProvider?

}
