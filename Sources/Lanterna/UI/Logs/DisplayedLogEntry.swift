import Foundation

// MARK: - DisplayedVersion

/// The on-screen version, straight from the generated file.
struct DisplayedVersion: Equatable {
  /// The full describe string, exactly as `Version.swift` holds it.
  let full: String
}

// MARK: - DisplayedLogEntry

/// One log row as the view shows it.
struct DisplayedLogEntry: Identifiable, Equatable {
  /// The store sequence, proving the order.
  let sequence: UInt64
  /// When the line was emitted, for reading only.
  let capturedAt: Date
  /// The line itself.
  let message: String

  var id: UInt64 {
    sequence
  }
}
