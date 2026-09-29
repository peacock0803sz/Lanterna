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
    }

    /// One action's row: its keys as chips, each removable and
    /// replaceable, with room to add one more.
    private func row(for action: KeyBindingAction, named name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
            HStack(spacing: 6) {
                ForEach(values.keyBindings[action].indices, id: \.self) { index in
                    let key = values.keyBindings[action][index]
                    Button(key.displayName) {
                        startCapture(action, slot: index)
                    }
                    .help("Press a replacement key")
                    .contextMenu {
                        Button("Remove") {
                            removeKey(action: action, at: index)
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

    /// Removes one key. An emptied row reads as defaults downstream,
    /// so removing the last key is a reset by another name.
    private func removeKey(action: KeyBindingAction, at index: Int) {
        stopCapture()
        var keys = values.keyBindings[action]
        guard keys.indices.contains(index) else { return }
        keys.remove(at: index)
        values.keyBindings.keys[action] = keys
        notice = nil
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
    /// reports with the press is narrowed away first.
    private func assign(
        action: KeyBindingAction, slot: Int?, keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) {
        let narrowed = modifiers.intersection([.shift, .control, .option, .command])
        let key = ResolvedKey(keyCode: keyCode, modifiers: narrowed)
        guard KeyBindingTable.allows(modifiers: narrowed, mode: action.mode) else {
            notice = "\(key.displayName) needs Cmd, Ctrl or Opt for this action."
            stopCapture()
            return
        }
        let holders = values.keyBindings.holders(of: key, except: action)
        guard holders.isEmpty else {
            let names = holders.map { displayName(for: $0) }.joined(separator: ", ")
            notice = "\(key.displayName) is already used by \(names)."
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

    /// The row name for an action, for the duplicate notice.
    private func displayName(for action: KeyBindingAction) -> String {
        Self.rows.first { $0.0 == action }?.1 ?? action.rawValue
    }
}
