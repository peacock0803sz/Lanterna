import SwiftUI

/// The label side of every settings row.
///
/// Every row, whether toggle, choice, or other control, keeps its heading
/// and its note here, so headings read alike across tabs.
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
