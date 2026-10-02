import SwiftUI

// MARK: - SettingsGroupsView

/// The Groups tab: whether the list groups its rows, and where each kind
/// of parked section goes once it does.
///
/// Grouping off shows the one choice and nothing else, since the
/// placements change nothing then.
struct SettingsGroupsView: View {

  // MARK: Internal

  @Binding var values: SettingsValues

  var body: some View {
    Form {
      Section("Grouping") {
        Picker(selection: $values.grouping.mode) {
          Text("Don't group").tag(GroupingMode.none)
          Text("By Space").tag(GroupingMode.bySpace)
        } label: {
          SettingsFormLabel(
            title: "Group windows",
            caption: "Keep one list, or group rows by the Space they live on, shown Spaces first."
          )
        }
        .pickerStyle(.menu)
      }
      if values.grouping.mode != .none {
        Section {
          ForEach(Self.placementRows, id: \.subgroup) { row in
            Picker(selection: placement(of: row.subgroup)) {
              Text("End of list").tag(SubgroupPlacement.endOfList)
              Text("Within each group").tag(SubgroupPlacement.withinGroup)
            } label: {
              SettingsFormLabel(title: row.title)
            }
            .pickerStyle(.menu)
            .disabled(isFixed(row.subgroup))
          }
        } header: {
          Text("Placement when grouped")
        } footer: {
          Text(placementFooter)
        }
      }
    }
    .formStyle(.grouped)
    .settingsBackground()
  }

  // MARK: Private

  /// One row per kind of parked section, in drawing order.
  private static let placementRows: [(subgroup: DisplaySubgroup, title: String)] = [
    (.otherSpace, "Windows on other spaces"),
    (.hiddenApp, "Windows of hidden apps"),
    (.minimized, "Minimized windows"),
    (.fullscreen, "Fullscreen windows"),
    (.windowlessApp, "Apps without windows"),
  ]

  private var placementFooter: String {
    let base = "Only kinds set to Separate at bottom in Filter are placed. End of list puts their section after "
      + "every group; Within each group puts it after that group's rows."
    guard values.grouping.mode == .bySpace else { return base }
    return base + " By Space files other-Space windows into their own Space groups and keeps apps without "
      + "windows after the last group, so those two rows are dimmed."
  }

  /// Whether grouping by Space already decides where this kind goes.
  private func isFixed(_ subgroup: DisplaySubgroup) -> Bool {
    values.grouping.mode == .bySpace && (subgroup == .otherSpace || subgroup == .windowlessApp)
  }

  private func placement(of subgroup: DisplaySubgroup) -> Binding<SubgroupPlacement> {
    Binding(
      get: { values.grouping.placement(of: subgroup) },
      set: { values.grouping.placements[subgroup] = $0 }
    )
  }

}
