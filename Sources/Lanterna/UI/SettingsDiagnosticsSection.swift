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
  /// Switches saving on or off now; off with `deleting` also removes
  /// every saved launch. The setting itself is saved by the caller.
  var applySaving: (_ saving: Bool, _ deleting: Bool) -> Void = { _, _ in }
}

// MARK: - SettingsDiagnosticsSection

/// The Diagnostics section of the General tab: the log window, saving to
/// disk, and the launches saved so far.
struct SettingsDiagnosticsSection: View {

  // MARK: Internal

  @Binding var values: SettingsValues
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
      Toggle(isOn: savingBinding) {
        SettingsFormLabel(
          title: "Save logs to disk",
          caption: "Each launch appends its lines to a text file, so the previous launch can be read after a "
            + "restart. Window titles are included. Recent launches are kept; older ones are removed."
        )
      }
      .alert("Delete saved logs too?", isPresented: $isConfirmingOff) {
        Button("Delete Saved Logs", role: .destructive) { setSaving(false, deleting: true) }
        Button("Keep Saved Logs") { setSaving(false, deleting: false) }
        Button("Cancel", role: .cancel) { }
      } message: {
        Text("Lanterna stops writing log lines to disk. The logs saved so far can be deleted now or kept.")
      }
      if let summary = display.savedSummary {
        HStack {
          SettingsFormLabel(
            title: "Saved logs",
            caption: "\(summary). Turning off Save logs to disk asks whether to delete these too."
          )
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
  @State private var isConfirmingOff = false

  /// On applies at once; off asks first whether the saved logs go too.
  private var savingBinding: Binding<Bool> {
    Binding(
      get: { values.saveLogsToDisk },
      set: { saving in
        if saving {
          setSaving(true, deleting: false)
        } else {
          isConfirmingOff = true
        }
      }
    )
  }

  private func setSaving(_ saving: Bool, deleting: Bool) {
    display.applySaving(saving, deleting)
    values.saveLogsToDisk = saving
  }

}
