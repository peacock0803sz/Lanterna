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
  /// What this run holds onto, refreshed when the settings open and
  /// after the saved logs change. Nil when the log window is not up.
  @Published var retention: RetentionSnapshot?
  /// Reads the retention numbers again. Wired by the delegate, which
  /// owns the holders.
  var refreshRetention: () -> Void = { }
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
      if let retention = display.retention {
        SettingsFormLabel(
          title: "Retention",
          caption: "What this run holds onto, as count / cap. Uncapped items show their count alone."
        )
        retentionRow(title: "Log rows", value: "\(retention.liveRows) / \(retention.liveRowsLimit)")
        if retention.logPaused {
          retentionRow(title: "Waiting rows", value: "\(retention.waitingRows) / \(retention.waitingRowsLimit)")
        }
        retentionRow(
          title: "Saved log bytes",
          value: "\(Self.megabytes(retention.savedBytes)) / \(Self.megabytes(retention.savedBytesLimit))"
        )
        retentionRow(title: "App icons", value: "\(retention.iconCount)")
        retentionRow(title: "Shortcut memory", value: "\(retention.shortcutCount) / \(retention.shortcutLimit)")
        retentionRow(
          title: "Recent uses",
          value: "\(retention.mruRecords) windows · \(retention.mruApplications) apps"
        )
        retentionRow(title: "Mirrored log lines", value: "\(retention.mirrorRows) / \(retention.mirrorRowsLimit)")
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

  private static func megabytes(_ bytes: Int) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_048_576)
  }

  private func retentionRow(title: String, value: String) -> some View {
    HStack {
      SettingsFormLabel(title: title)
      Spacer()
      Text(value)
    }
  }

  private func setSaving(_ saving: Bool, deleting: Bool) {
    display.applySaving(saving, deleting)
    values.saveLogsToDisk = saving
  }

}
