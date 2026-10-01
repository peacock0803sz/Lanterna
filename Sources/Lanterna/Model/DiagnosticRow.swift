import Foundation

/// One persisted diagnostic line: what reached the mirror, with when and
/// in what order, plus the fields the on-screen views filter on.
///
/// The message keeps the exact bytes stderr received, so the existing
/// grep flow keeps working. Everything else rides alongside and never
/// leaks into the emitted line.
struct DiagnosticRow: Equatable, Sendable, Codable {
  /// Order within one launch. Starts at one for each launch.
  let sequence: UInt64
  /// When the line was recorded, as milliseconds since the epoch.
  /// A plain number keeps every locale reading the same instant.
  let recordedAtMilliseconds: Int64
  /// One of error, warning, info, debug. Matches the logger words.
  let level: String
  /// Where the line comes from, such as panel or ax. Absent when
  /// the caller attached no grouping.
  let category: String?
  /// The line itself, byte for byte what stderr received.
  let message: String
  /// Which launch emitted the line.
  let launchID: String?
  /// Which build emitted the line.
  let buildVersion: String?
  /// Extra context kept as JSON text, so nested keys and arrays
  /// survive the round trip without a migration per key.
  let payloadJSON: String?
}
