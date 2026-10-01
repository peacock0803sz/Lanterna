import SwiftUI

// MARK: - LiveIndicator

/// Whether new lines are being added as they arrive, and how many wait
/// while they are not.
struct LiveIndicator: View {

  let isPaused: Bool
  let pendingCount: Int

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(Color(nsColor: isPaused ? .systemOrange : .systemGreen))
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)
      Text(Self.text(isPaused: isPaused, pendingCount: pendingCount))
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }

  static func text(isPaused: Bool, pendingCount: Int) -> String {
    guard isPaused else { return "Live" }
    let entries = pendingCount == 1 ? "entry" : "entries"
    return "Paused · \(pendingCount) new matching \(entries) waiting"
  }

}

// MARK: - ToolbarIconButton

/// A square icon button in the toolbar's row, tinted when it stands for
/// the state the window is in.
struct ToolbarIconButton: View {

  let systemImage: String
  let label: String
  /// Shown after the label in the tooltip, never read aloud.
  var shortcut: String?
  var isProminent = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 12, weight: .medium))
        .frame(width: 28, height: 26)
        .foregroundStyle(isProminent ? Color.white : Color.secondary)
        .background(
          isProminent ? Color.accentColor : Color.primary.opacity(0.04),
          in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(shortcut.map { "\(label) (\($0))" } ?? label)
    .accessibilityLabel(label)
  }

}

// MARK: - PausedBar

/// The strip over a paused table: says the list holds still, and offers
/// the waiting lines.
struct PausedBar: View {

  // MARK: Internal

  let pendingCount: Int
  let resume: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text("Paused — the list holds still until you resume")
        .font(.system(size: 11))
        .foregroundStyle(Self.ink)
      Spacer(minLength: 8)
      Button(action: resume) {
        HStack(spacing: 4) {
          Image(systemName: "arrow.down")
            .font(.system(size: 9, weight: .bold))
          Text("\(pendingCount) new · Resume to show")
            .font(.system(size: 11))
        }
        .foregroundStyle(Color(nsColor: .systemOrange))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color(nsColor: .systemOrange).opacity(0.12), in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Resume and show \(pendingCount) new entries")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 6)
    .background(Color(nsColor: .systemOrange).opacity(0.08))
  }

  // MARK: Private

  private static let ink = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? .systemOrange
      : NSColor(red: 0.54, green: 0.35, blue: 0, alpha: 1)
  })

}
