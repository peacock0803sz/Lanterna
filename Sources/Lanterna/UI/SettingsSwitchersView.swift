import SwiftUI

// MARK: - SwitcherTab

/// The sub-tabs of the Switchers tab, one per switcher.
private enum SwitcherTab: Hashable {
  case main
  case parallel
}

// MARK: - SwitcherLink

/// Whether an Opt+Tab row follows Cmd+Tab, and how to flip it.
private struct SwitcherLink {
  let isLinked: Bool
  let toggle: () -> Void
}

// MARK: - SwitcherRow

/// One per-switcher row: the same label, choices, and caption on both
/// sub-tabs, with a link button on the Opt+Tab side alone. A linked row
/// shows the Cmd+Tab value, dimmed and fixed.
private struct SwitcherRow<Value: Hashable & Sendable>: View {
  let title: String
  let caption: String?
  let choices: [(String, Value)]
  let link: SwitcherLink?
  let isFixed: Bool

  @Binding var value: Value

  var body: some View {
    LabeledContent {
      HStack {
        Picker(title, selection: $value) {
          ForEach(choices.indices, id: \.self) { offset in
            Text(choices[offset].0).tag(choices[offset].1)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(isFixed || link?.isLinked == true)
        .opacity(link?.isLinked == true ? 0.4 : 1)
        if let link {
          Button(action: link.toggle) {
            Image(systemName: "link")
              .foregroundStyle(link.isLinked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
          }
          .buttonStyle(.borderless)
          .help(link.isLinked ? "Linked to Cmd+Tab. Click to give Opt+Tab its own value." : "Link to Cmd+Tab")
          .accessibilityLabel(link.isLinked ? "Unlink from Cmd+Tab" : "Link to Cmd+Tab")
        }
      }
    } label: {
      SettingsFormLabel(title: title, caption: caption)
    }
  }
}

// MARK: - SettingsSwitchersView

/// The Switchers tab: the parallel switcher's switch, then one sub-tab
/// per switcher holding its invocation keys, its window list, and where
/// the parked kinds go when grouped.
///
/// Both sub-tabs lay out the same rows with the same words. The Opt+Tab
/// rows link to Cmd+Tab by default; only the window scope starts on its
/// own value, the active application.
struct SettingsSwitchersView: View {

  // MARK: Internal

  @Binding var values: SettingsValues

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $values.parallelOverrides.isEnabled) {
          SettingsFormLabel(
            title: "Parallel switcher (Opt+Tab)",
            caption: "A second panel with its own settings. "
              + "Off hands Opt+Tab back to the front application; its settings are kept."
          )
        }
        Toggle(isOn: $values.listWindowsOnAllSpaces) {
          SettingsFormLabel(
            title: "Windows on all desktops",
            caption: "List windows on every Mission Control desktop, not only the ones showing. "
              + "Lanterna asks each app for more in the background, which uses more CPU."
          )
        }
      } footer: {
        VStack(spacing: 6) {
          tabPicker
          Text(paneCaption)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
      }
      Section("Invocation") {
        LabeledContent {
          HStack {
            ForEach(invocationKeys, id: \.self) { name in
              Text(name)
                .font(.callout)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
          }
        } label: {
          SettingsFormLabel(title: "Keys", caption: "Change them in Keyboard.")
        }
      }
      Section("Window types") {
        SwitcherRow(
          title: "Show windows of",
          caption: "List every app's windows, or only the active app's when the panel opens. "
            + "The panel key switches it for one showing.",
          choices: Self.scopes,
          link: link(\.windowScope, main: values.windowScope),
          isFixed: false,
          value: scope
        )
        ForEach(Self.modeRows, id: \.subgroup) { row in
          SwitcherRow(
            title: row.title,
            caption: row.caption,
            choices: Self.modes,
            link: link(Self.modePath(row.subgroup), main: values.displayModes[keyPath: Self.mainModePath(row.subgroup)]),
            isFixed: false,
            value: mode(of: row.subgroup)
          )
        }
      }
      Section {
        ForEach(Self.modeRows, id: \.subgroup) { row in
          SwitcherRow(
            title: row.title,
            caption: nil,
            choices: Self.placements,
            link: link(Self.placementPath(row.subgroup), main: values.grouping.placement(of: row.subgroup)),
            isFixed: isFixed(row.subgroup),
            value: placement(of: row.subgroup)
          )
        }
      } header: {
        Text("Placement when grouped")
      } footer: {
        Text(placementFooter)
      }
      if tab == .parallel {
        Section {
          HStack {
            Spacer()
            Button("Link all to Cmd+Tab") {
              let isEnabled = values.parallelOverrides.isEnabled
              values.parallelOverrides = ParallelOverrides(windowScope: .follow, isEnabled: isEnabled)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .settingsBackground()
  }

  // MARK: Private

  /// One row per kind of special window, in drawing order.
  private static let modeRows: [(subgroup: DisplaySubgroup, title: String, caption: String)] = [
    (
      .otherSpace,
      "Windows on other spaces",
      "Windows living on another Space: mix them in, keep them out, or park them below."
    ),
    (
      .hiddenApp,
      "Windows of hidden apps",
      "Windows of hidden applications: mix them in, keep them out, or park them below."
    ),
    (
      .minimized,
      "Minimized windows",
      "Windows folded into the Dock: mix them in, keep them out, or park them below."
    ),
    (
      .fullscreen,
      "Fullscreen windows",
      "Windows filling their own Space: mix them in, keep them out, or park them below."
    ),
    (
      .windowlessApp,
      "Apps without windows",
      "Running apps with no open window: mix them in, keep them out, or park them below. "
        + "Choosing one brings the app forward."
    ),
  ]

  private static let scopes: [(String, WindowScope)] = [
    ("All apps", .allApps),
    ("Active app", .frontApp),
  ]

  private static let modes: [(String, DisplayMode)] = [
    ("Show", .show),
    ("Hide", .hide),
    ("Separate at bottom", .separateAtBottom),
  ]

  private static let placements: [(String, SubgroupPlacement)] = [
    ("End of list", .endOfList),
    ("Within each group", .withinGroup),
  ]

  /// Which sub-tab is showing. Opens on Cmd+Tab every time.
  @State private var tab = SwitcherTab.main

  private var tabPicker: some View {
    HStack(spacing: 2) {
      segment("Cmd+Tab", for: .main, isOn: nil)
      segment("Opt+Tab", for: .parallel, isOn: values.parallelOverrides.isEnabled)
    }
    .padding(2)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    .fixedSize()
  }

  private var paneCaption: String {
    switch tab {
    case .main:
      let filter = values.keyBindings[.showFilter].first?.displayName ?? "its key"
      return "Show for filtering (\(filter)) opens with these settings too."

    case .parallel:
      return "Linked rows follow Cmd+Tab. Unlink a row to give Opt+Tab its own value."
    }
  }

  /// The invocation keys of the sub-tab showing, as the Keyboard tab
  /// names them.
  private var invocationKeys: [String] {
    let actions: [KeyBindingAction] = tab == .main
      ? [.show, .showReverse, .showFilter]
      : [.showParallel, .showParallelReverse]
    return actions.flatMap { values.keyBindings[$0].map(\.displayName) }
  }

  private var placementFooter: String {
    let base = "Only kinds set to Separate at bottom above are placed, and only while Group windows in Groups "
      + "is not Don't group. End of list puts their section after every group; Within each group puts it "
      + "after that group's rows."
    guard values.grouping.mode == .bySpace else { return base }
    return base + " By Space files other-Space windows into their own Space groups and keeps apps without "
      + "windows after the last group, so those two rows are dimmed."
  }

  private var scope: Binding<WindowScope> {
    switch tab {
    case .main: $values.windowScope
    case .parallel: parallel(\.windowScope, main: values.windowScope)
    }
  }

  /// The Cmd+Tab display mode of one kind.
  private static func mainModePath(_ subgroup: DisplaySubgroup) -> WritableKeyPath<DisplayModes, DisplayMode> {
    switch subgroup {
    case .otherSpace: \.otherSpace
    case .hiddenApp: \.hiddenApp
    case .minimized: \.minimized
    case .fullscreen: \.fullscreen
    case .windowlessApp: \.windowlessApp
    }
  }

  /// The parallel override behind one kind's display mode.
  private static func modePath(
    _ subgroup: DisplaySubgroup
  ) -> WritableKeyPath<ParallelOverrides, FollowOrOwn<DisplayMode>> {
    switch subgroup {
    case .otherSpace: \.otherSpaceMode
    case .hiddenApp: \.hiddenAppMode
    case .minimized: \.minimizedMode
    case .fullscreen: \.fullscreenMode
    case .windowlessApp: \.windowlessAppMode
    }
  }

  /// The parallel override behind one kind's placement.
  private static func placementPath(
    _ subgroup: DisplaySubgroup
  ) -> WritableKeyPath<ParallelOverrides, FollowOrOwn<SubgroupPlacement>> {
    switch subgroup {
    case .otherSpace: \.otherSpacePlacement
    case .hiddenApp: \.hiddenAppPlacement
    case .minimized: \.minimizedPlacement
    case .fullscreen: \.fullscreenPlacement
    case .windowlessApp: \.windowlessAppPlacement
    }
  }

  private func segment(_ title: String, for target: SwitcherTab, isOn: Bool?) -> some View {
    Button {
      tab = target
    } label: {
      HStack(spacing: 6) {
        Text(title)
          .fontWeight(tab == target ? .semibold : .regular)
        if let isOn {
          Circle()
            .fill(isOn ? Color.green : Color.secondary.opacity(0.5))
            .frame(width: 6, height: 6)
            .accessibilityLabel(isOn ? "On" : "Off")
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 3)
      .background {
        if tab == target {
          RoundedRectangle(cornerRadius: 5)
            .fill(Color(nsColor: .controlColor))
            .shadow(color: .black.opacity(0.15), radius: 0.75, y: 0.5)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func mode(of subgroup: DisplaySubgroup) -> Binding<DisplayMode> {
    let path = Self.mainModePath(subgroup)
    switch tab {
    case .main:
      return $values.displayModes[dynamicMember: path]
    case .parallel:
      return parallel(Self.modePath(subgroup), main: values.displayModes[keyPath: path])
    }
  }

  private func placement(of subgroup: DisplaySubgroup) -> Binding<SubgroupPlacement> {
    switch tab {
    case .main:
      Binding(
        get: { values.grouping.placement(of: subgroup) },
        set: { values.grouping.placements[subgroup] = $0 }
      )

    case .parallel:
      parallel(Self.placementPath(subgroup), main: values.grouping.placement(of: subgroup))
    }
  }

  /// The value an Opt+Tab row shows: its own, or the Cmd+Tab value while
  /// linked. Setting it owns the value.
  private func parallel<Value>(
    _ path: WritableKeyPath<ParallelOverrides, FollowOrOwn<Value>>,
    main: Value
  ) -> Binding<Value> {
    Binding(
      get: { values.parallelOverrides[keyPath: path].resolved(with: main) },
      set: { values.parallelOverrides[keyPath: path] = .own($0) }
    )
  }

  /// The link button of an Opt+Tab row, or none on the Cmd+Tab side.
  /// Unlinking starts from the Cmd+Tab value; linking drops the own value.
  private func link<Value>(
    _ path: WritableKeyPath<ParallelOverrides, FollowOrOwn<Value>>,
    main: Value
  ) -> SwitcherLink? {
    guard tab == .parallel else { return nil }
    let isLinked = values.parallelOverrides[keyPath: path] == .follow
    return SwitcherLink(isLinked: isLinked) {
      if isLinked {
        values.parallelOverrides[keyPath: path] = .own(main)
      } else {
        values.parallelOverrides[keyPath: path] = .follow
      }
    }
  }

  /// Whether grouping by Space already decides where this kind goes.
  private func isFixed(_ subgroup: DisplaySubgroup) -> Bool {
    values.grouping.mode == .bySpace && (subgroup == .otherSpace || subgroup == .windowlessApp)
  }

}
