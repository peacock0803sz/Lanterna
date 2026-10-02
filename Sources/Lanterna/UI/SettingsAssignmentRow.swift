import SwiftUI

// MARK: - SettingsAssignmentRow

/// One application assigned to one manual group: its icon, its bundle
/// identifier and what that names, the group it goes to, and Remove.
struct SettingsAssignmentRow: View {

  // MARK: Internal

  @Binding var entry: GroupAssignment

  /// The rows above this one, which decide whether it repeats one.
  let earlier: [GroupAssignment]
  let groupCount: Int
  let names: [Int: String]
  let onRemove: () -> Void

  var body: some View {
    HStack(alignment: .top) {
      Image(nsImage: AppIconResolver.icon(forBundleIdentifier: iconIdentifier))
        .resizable()
        .frame(width: 22, height: 22)
      VStack(alignment: .leading) {
        TextField("Bundle ID", text: $entry.bundleID)
        Text(note.text)
          .font(.system(size: 11))
          .foregroundStyle(note.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
      }
      Picker("Group", selection: $entry.group) {
        ForEach(1 ... AppConfiguration.maximumGroupCount, id: \.self) { group in
          if group <= groupCount {
            Text(label(of: group)).tag(group)
          } else if group == entry.group {
            Text("Group \(group) (inactive)").tag(group)
          }
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: 150)
      Button("Remove", action: onRemove)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
  }

  // MARK: Private

  private var note: AssignmentNote {
    AssignmentAppResolver.note(for: entry.bundleID, earlier: earlier)
  }

  private var iconIdentifier: String? {
    if case .found(_, let bundleIdentifier) = note {
      return bundleIdentifier
    }
    if case .notRunning = note {
      return entry.bundleID
    }
    return nil
  }

  private func label(of group: Int) -> String {
    guard let name = names[group], !name.trimmingCharacters(in: .whitespaces).isEmpty else {
      return "Group \(group)"
    }
    return "Group \(group) · \(name)"
  }

}
