import SwiftUI

// MARK: - SettingsManualGroupRows

/// The rows of the Grouping section that only manual grouping has: how
/// many groups, and what their headings say.
struct SettingsManualGroupRows: View {

  @Binding var grouping: GroupingPolicy

  var body: some View {
    LabeledContent {
      HStack {
        Text("\(grouping.groupCount)")
        Stepper(
          "Number of groups",
          value: $grouping.groupCount,
          in: 1 ... AppConfiguration.maximumGroupCount
        )
        .labelsHidden()
      }
    } label: {
      SettingsFormLabel(
        title: "Number of groups",
        caption: "Groups 1 to 9. Lowering it keeps assignments and names; they come back when it grows."
      )
    }
    Picker(selection: $grouping.headingStyle) {
      Text("Number").tag(GroupHeadingStyle.number)
      Text("Name").tag(GroupHeadingStyle.name)
      Text("App names").tag(GroupHeadingStyle.appNames)
    } label: {
      SettingsFormLabel(
        title: "Group headings",
        caption: "Show the group number, the name you give it, or the names of the apps in it."
      )
    }
    .pickerStyle(.menu)
  }

}

// MARK: - SettingsManualGroupSections

/// The sections only manual grouping has: a name for each group, and the
/// applications assigned to them.
struct SettingsManualGroupSections: View {

  // MARK: Internal

  @Binding var grouping: GroupingPolicy

  var body: some View {
    Section {
      ForEach(1 ... grouping.groupCount, id: \.self) { group in
        HStack {
          Text("\(group)")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
          TextField("Group \(group)", text: name(of: group))
          Text(appCountWording(group))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }
    } header: {
      Text("Groups")
    } footer: {
      Text("A group without a name shows its number. Names only show when Group headings is Name.")
    }
    Section {
      DisclosureGroup(isExpanded: $assignmentsShown) {
        ForEach($grouping.assignments) { $entry in
          SettingsAssignmentRow(
            entry: $entry,
            earlier: rows(before: entry.id),
            groupCount: grouping.groupCount,
            names: grouping.names,
            onRemove: { grouping.assignments.removeAll { $0.id == entry.id } }
          )
        }
        HStack {
          Menu("Add Running App…") {
            ForEach(runningApps, id: \.bundleIdentifier) { app in
              Button(app.name) {
                grouping.assignments.append(GroupAssignment(bundleID: app.bundleIdentifier, group: 1))
              }
              .disabled(isAssigned(app.bundleIdentifier))
            }
          }
          .fixedSize()
          Button("Add by Bundle ID") {
            grouping.assignments.append(GroupAssignment(bundleID: "", group: 1))
          }
        }
        .controlSize(.small)
      } label: {
        HStack {
          Text("App assignments")
          Spacer()
          Text(assignmentSummary)
            .font(.system(size: 11))
            .foregroundStyle(missingCount > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
      }
    } footer: {
      if assignmentsShown {
        Text("Apps not listed here, and apps assigned past the group count, go to Group 1. Each app can sit in "
          + "one group only; running apps already listed are greyed out in the menu.")
      }
    }
  }

  // MARK: Private

  /// Folded by default and never saved: the list is reference, and a long
  /// one would otherwise push the placements off the tab.
  @State private var assignmentsShown = false

  /// The running applications that have a bundle identifier, by name.
  private var runningApps: [ResolvedExclusionApp] {
    RunningApplicationInfo.regularApplications()
      .compactMap { app in app.bundleIdentifier.map { ResolvedExclusionApp(name: app.name, bundleIdentifier: $0) } }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private var missingCount: Int {
    grouping.assignments.count { entry in
      AssignmentAppResolver.note(for: entry.bundleID, earlier: rows(before: entry.id)) == .missing
    }
  }

  /// "N apps · M groups", or the count not found when there is one. M
  /// counts the groups holding an assignment, past-count ones as group 1.
  private var assignmentSummary: String {
    let count = grouping.assignments.count
    let apps = count == 1 ? "1 app" : "\(count) apps"
    if missingCount > 0 {
      return "\(apps) · \(missingCount) not found"
    }
    let groups = Set(grouping.assignments.map { grouping.group(forBundleID: $0.bundleID) }).count
    return "\(apps) · \(groups == 1 ? "1 group" : "\(groups) groups")"
  }

  private func rows(before id: UUID) -> [GroupAssignment] {
    Array(grouping.assignments.prefix { $0.id != id })
  }

  private func isAssigned(_ bundleID: String) -> Bool {
    grouping.assignments.contains { $0.bundleID.lowercased() == bundleID.lowercased() }
  }

  private func appCountWording(_ group: Int) -> String {
    let count = grouping.assignments.count { grouping.group(forBundleID: $0.bundleID) == group && $0.group == group }
    return count == 1 ? "1 app" : "\(count) apps"
  }

  private func name(of group: Int) -> Binding<String> {
    Binding(
      get: { grouping.names[group] ?? "" },
      set: { grouping.names[group] = $0 }
    )
  }

}
