import AppKit
import SwiftUI

/// The Keyboard tab: every action's keys, editable by pressing them.
///
/// Rows read from the shared values and write back through them, like
/// every other tab. An invalid press never reaches the values: the row
/// says why and keeps the old keys, so the file can never be saved
/// invalid from here.
struct SettingsKeyboardView: View {
    @Binding var values: SettingsValues
    /// The row waiting for a press, and which slot a press replaces.
    /// A `nil` slot appends instead.
    @State private var capturing: (action: KeyBindingAction, slot: Int?)?
    @State private var monitor: Any?
    @State private var notice: String?

    /// The rows in the file's action order, with the names users read.
    private static let rows: [(KeyBindingAction, String)] = [
        (.show, "Show"),
        (.showReverse, "Show in reverse"),
        (.showFilter, "Show for filtering"),
        (.next, "Next"),
        (.previous, "Previous"),
        (.commit, "Commit"),
        (.cancel, "Cancel"),
        (.deleteBackward, "Delete backward"),
        (.clearQuery, "Clear query"),
        (.closeWindow, "Close window"),
        (.quitApplication, "Quit application"),
        (.hideApplication, "Hide application"),
        (.minimizeWindow, "Minimize window"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.rows, id: \.0) { action, name in
                    row(for: action, named: name)
                }
                HStack {
                    Button("Reset all") {
                        values.keyBindings = .defaults
                        stopCapture()
                        notice = nil
                    }
                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Press a key to assign it. Assignments are physical keys, independent of input source.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .onDisappear(perform: stopCapture)
    }

    /// One action's row: its keys as chips, each removable and
    /// replaceable, with room to add one more.
    private func row(for action: KeyBindingAction, named name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
            HStack(spacing: 6) {
                ForEach(values.keyBindings[action], id: \.self) { key in
                    Button(key.displayName) {
                        startCapture(action, slot: values.keyBindings[action].firstIndex(of: key))
                    }
                    .help("Press a replacement key")
                    .contextMenu {
                        Button("Remove") {
                            if let slot = values.keyBindings[action].firstIndex(of: key) {
                                removeKey(action: action, at: slot)
                            }
                        }
                    }
                }
                Button("Add") {
                    startCapture(action, slot: nil)
                }
                .help("Press an additional key")
                Button("Reset") {
                    values.keyBindings.keys[action] = KeyBindingTable.defaults[action]
                    stopCapture()
                    notice = nil
                }
                .help("Restore the default keys")
                if capturing?.action == action {
                    Button("Cancel") {
                        stopCapture()
                        notice = nil
                    }
                }
            }
            if capturing?.action == action {
                Text("Press a key…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Removes one key. Removing the last key restores the row's defaults
    /// with a notice, because an emptied row would read as defaults
    /// downstream while looking empty here.
    private func removeKey(action: KeyBindingAction, at index: Int) {
        stopCapture()
        var keys = values.keyBindings[action]
        guard keys.indices.contains(index) else { return }
        keys.remove(at: index)
        if keys.isEmpty {
            keys = KeyBindingTable.defaults[action]
            notice = "Removing the last key restored \(displayName(for: action)) defaults."
        } else {
            notice = nil
        }
        values.keyBindings.keys[action] = keys
    }

    /// Arms the capture: the next key down goes to this row.
    private func startCapture(_ action: KeyBindingAction, slot: Int?) {
        stopCapture()
        capturing = (action, slot)
        notice = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            assign(action: action, slot: slot, keyCode: event.keyCode, modifiers: event.modifierFlags)
            return nil
        }
    }

    /// Takes the capture down. A press that arrived stays assigned;
    /// only the waiting ends here.
    private func stopCapture() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        capturing = nil
    }

    /// Assigns the pressed key, refusing what the table would refuse.
    /// Only the four schema modifiers count: anything else the keyboard
    /// reports with the press is narrowed away first. The rules themselves
    /// live with the table, so this only words the refusal.
    private func assign(
        action: KeyBindingAction, slot: Int?, keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) {
        let narrowed = modifiers.intersection([.shift, .control, .option, .command])
        let key = ResolvedKey(keyCode: keyCode, modifiers: narrowed)
        let row = displayName(for: action)
        switch KeyBindingTable.refusal(assigning: key, to: action, in: values.keyBindings) {
        case .none:
            break
        case .needsModifiers:
            notice = "\(key.displayName) needs Cmd, Ctrl or Opt for \(row)."
            stopCapture()
            return
        case .alreadyHeld:
            notice = "\(row) already holds \(key.displayName)."
            stopCapture()
            return
        case let .heldBy(holders):
            let names = holders.map { displayName(for: $0) }.joined(separator: ", ")
            notice = "\(key.displayName) is already used by \(names); not added to \(row)."
            stopCapture()
            return
        }
        var keys = values.keyBindings[action]
        if let slot, keys.indices.contains(slot) {
            keys[slot] = key
        } else {
            keys.append(key)
        }
        values.keyBindings.keys[action] = keys
        stopCapture()
        notice = nil
    }

    /// The row name for an action, for the notices naming the edited row.
    private func displayName(for action: KeyBindingAction) -> String {
        Self.rows.first { $0.0 == action }?.1 ?? action.rawValue
    }
}
