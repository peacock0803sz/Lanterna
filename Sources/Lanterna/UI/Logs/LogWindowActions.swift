import AppKit
import UniformTypeIdentifiers

/// Copying and exporting what the log window shows.
extension LogWindowState {

  // MARK: Internal

  /// What Copy and ⌘C take: the selected lines on screen, or every line
  /// on screen when none is selected.
  var copyTargets: [Diagnostics.LogEntry] {
    let selected = selectedEntries
    return selected.isEmpty ? shownEntries : selected
  }

  /// The lines on screen, separators left out, oldest first.
  var shownEntries: [Diagnostics.LogEntry] {
    shownRows.compactMap(\.entry)
  }

  /// Whether Copy and Export… have anything to take.
  var canCopyOrExport: Bool {
    shownRows.contains { !$0.isSeparator }
  }

  /// Puts the copy targets on the pasteboard as text. Does nothing when
  /// there is nothing on screen, so an empty copy is never made.
  func copy(to pasteboard: NSPasteboard = .general) {
    copy(copyTargets, to: pasteboard)
  }

  /// Puts the lines with `ids` on the pasteboard, in table order.
  func copy(rowsWithIDs ids: Set<LogRow.ID>, to pasteboard: NSPasteboard = .general) {
    copy(shownRows.compactMap { ids.contains($0.id) ? $0.entry : nil }, to: pasteboard)
  }

  /// Writes every line on screen to `url` as JSON Lines.
  func export(to url: URL) throws {
    try Data(LogExport.jsonLines(shownEntries).utf8).write(to: url, options: .atomic)
  }

  /// Asks where to save, then writes. A failed write is said in an alert;
  /// logging and the window carry on either way.
  func exportWithPanel(attachedTo window: NSWindow?) {
    guard canCopyOrExport else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = LogExport.defaultFileName(at: Date())
    panel.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .json]
    panel.canCreateDirectories = true
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let url = panel.url, let self else { return }
      do {
        try export(to: url)
      } catch {
        Self.alertExportFailed(error, attachedTo: window)
      }
    }
    if let window {
      panel.beginSheetModal(for: window, completionHandler: finish)
    } else {
      finish(panel.runModal())
    }
  }

  // MARK: Private

  private static func alertExportFailed(_ error: any Error, attachedTo window: NSWindow?) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Couldn’t export the logs"
    alert.informativeText = error.localizedDescription
    if let window {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }

  private func copy(_ entries: [Diagnostics.LogEntry], to pasteboard: NSPasteboard) {
    guard !entries.isEmpty else { return }
    pasteboard.clearContents()
    pasteboard.setString(LogExport.copyText(entries), forType: .string)
  }

}
