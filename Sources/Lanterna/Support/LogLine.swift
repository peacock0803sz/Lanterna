import Logging

/// One diagnostics line on its way out: what it says and where it came from.
///
/// The initializer's defaults capture the call site, so a line passed
/// through an injected closure still names the file that wrote it rather
/// than the closure or `Diagnostics`.
struct LogLine: Equatable, Sendable {

  // MARK: Lifecycle

  init(
    _ level: Logger.Level,
    _ category: LogCategory,
    _ message: String,
    context: [String: ContextValue] = [:],
    file: String = #fileID,
    line: UInt = #line
  ) {
    self.level = level
    self.category = category
    self.message = message
    self.context = context
    self.file = file
    self.line = line
  }

  // MARK: Internal

  let level: Logger.Level
  let category: LogCategory
  /// What stderr receives, byte for byte.
  let message: String
  let context: [String: ContextValue]
  /// The call site as `#fileID` gives it (`Module/File.swift`).
  let file: String
  let line: UInt

}
