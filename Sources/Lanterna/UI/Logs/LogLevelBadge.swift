import AppKit
import Logging
import SwiftUI

// MARK: - Logger.Level + shortName

extension Logger.Level {
  /// The word the badge, the copied text and the detail pane use.
  var shortName: String {
    switch self {
    case .error,
         .critical: "ERROR"
    case .warning: "WARN"
    case .info,
         .notice: "INFO"
    case .debug,
         .trace: "DEBUG"
    }
  }
}

// MARK: - LogLevelBadge

/// A line's level as a coloured token, readable in both appearances.
///
/// The text takes a darker shade in the light appearance and the system
/// colour in the dark one, so the word keeps its contrast on the tint.
struct LogLevelBadge: View {

  // MARK: Internal

  let level: Logger.Level

  var body: some View {
    Text(level.shortName)
      .font(.system(size: 10, weight: .bold, design: .monospaced))
      .foregroundStyle(tint)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
      .fixedSize()
      .accessibilityLabel("Level \(level.shortName)")
  }

  // MARK: Private

  private var tint: Color {
    switch level {
    case .error,
         .critical: Self.adaptive(light: NSColor(red: 0.84, green: 0, blue: 0.08, alpha: 1), dark: .systemRed)
    case .warning: Self.adaptive(light: NSColor(red: 0.78, green: 0.47, blue: 0, alpha: 1), dark: .systemOrange)
    case .info,
         .notice: Self.adaptive(light: NSColor(red: 0, green: 0.42, blue: 0.9, alpha: 1), dark: .systemBlue)
    case .debug,
         .trace: Color(nsColor: .secondaryLabelColor)
    }
  }

  private static func adaptive(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
  }

}
