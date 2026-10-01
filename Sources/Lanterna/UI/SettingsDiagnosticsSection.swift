import SwiftUI

// MARK: - DiagnosticsDisplay

/// What the Diagnostics section shows and does.
///
/// Owned by the settings window; the delegate fills in the actions and
/// refreshes the summary after deleting.
@MainActor
final class DiagnosticsDisplay: ObservableObject {
  /// The saved logs in brief, or nil when this run keeps none.
  @Published var savedSummary: String?
  var showLogs: () -> Void = { }
  var deleteSavedLogs: () -> Void = { }
}

// MARK: - SettingsDiagnosticsSection

/// The Diagnostics section of the General tab: the log window, and the
/// launches saved on disk.
struct SettingsDiagnosticsSection: View {

  // MARK: Internal

  @ObservedObject var display: DiagnosticsDisplay

  var body: some View {
    Section("Diagnostics") {
      HStack {
        SettingsFormLabel(title: "Logs", caption: "Watch events live, copy them, or export a file.")
        Spacer()
        Button("Show Logs…", action: display.showLogs)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
      if let summary = display.savedSummary {
        HStack {
          SettingsFormLabel(title: "Saved logs", caption: summary)
          Spacer()
          Button("Delete Saved Logs…") { isConfirmingDelete = true }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .alert("Delete saved logs?", isPresented: $isConfirmingDelete) {
          Button("Delete Saved Logs", role: .destructive, action: display.deleteSavedLogs)
          Button("Cancel", role: .cancel) { }
        } message: {
          Text("The logs of earlier launches are removed. This launch keeps its own.")
        }
      }
    }
  }

  // MARK: Private

  @State private var isConfirmingDelete = false

}
