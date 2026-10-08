import Foundation

/// Byte counts as the diagnostics show them.
enum ByteCountText {

  /// Bytes in the unit that reads best: whole bytes below 1 KB, one
  /// decimal KB below 1 MB, and one decimal MB from there up. Just under
  /// 1 MB, where one decimal KB would round up to `1024.0 KB`, MB is
  /// used already. Small reads would otherwise round to `0.0 MB`.
  static func text(_ bytes: Int) -> String {
    if bytes < 1024 {
      return "\(bytes) B"
    }
    // Avoid %.1f KB rounding up to 1024.0 KB just below 1 MB.
    if Double(bytes) / 1024 < 1023.95 {
      return String(format: "%.1f KB", Double(bytes) / 1024)
    }
    return String(format: "%.1f MB", Double(bytes) / 1_048_576)
  }

}
