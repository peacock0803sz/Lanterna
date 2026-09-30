import SwiftUI

// MARK: - SettingsFormLabel

/// The label side of a settings control row.
///
/// A heading with an optional note under it, so toggles, pickers, and
/// other labeled controls read alike across tabs.
struct SettingsFormLabel: View {
  init(title: String, caption: String? = nil) {
    self.title = title
    self.caption = caption
  }

  var body: some View {
    VStack(alignment: .leading) {
      Text(title)
      if let caption {
        Text(caption)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private let title: String
  private let caption: String?
}

// MARK: - SettingsBackground

extension View {
  /// The gray behind grouped settings content.
  func settingsBackground() -> some View {
    scrollContentBackground(.hidden)
      .background(Color(nsColor: .underPageBackgroundColor))
  }

  /// The sidebar gray, a touch darker than the detail.
  func settingsSidebarBackground() -> some View {
    scrollContentBackground(.hidden)
      .background {
        Color(nsColor: .underPageBackgroundColor)
          .overlay(Color.black.opacity(0.04))
      }
  }
}
