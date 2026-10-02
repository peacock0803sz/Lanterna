import AppKit
import SwiftUI

// MARK: - SettingsTab

/// The settings tabs in a fixed order.
enum SettingsTab: CaseIterable {
  case general
  case appearance
  case filter
  case groups
  case keyboard

  // MARK: Internal

  var title: String {
    switch self {
    case .general: "General"
    case .appearance: "Appearance"
    case .filter: "Filter"
    case .groups: "Groups"
    case .keyboard: "Keyboard"
    }
  }

  var iconName: String {
    switch self {
    case .general: "gearshape"
    case .appearance: "paintbrush"
    case .filter: "line.3.horizontal.decrease.circle"
    case .groups: "square.3.layers.3d"
    case .keyboard: "keyboard"
    }
  }
}

// MARK: - SettingsWindow

/// The settings window.
///
/// A regular window like the onboarding and version windows: it holds
/// controls the user clicks, so the non-activating switcher panel cannot
/// host them. Tabs share one model, so a change anywhere applies
/// everywhere at once through the single change handler.
@MainActor
final class SettingsWindow: NSWindow {

  // MARK: Lifecycle

  /// Builds the window showing the given values. Changes flow back
  /// through `onChange` as they happen; saving and confirmation live
  /// with the caller, not here.
  convenience init(
    values: SettingsValues,
    version: DisplayedVersion,
    permissionState: PermissionState,
    opener: @escaping SettingsOpener,
    appearanceMode: AppearanceMode = .system,
    onCheckNow: @escaping () -> Void = { },
    diagnostics: DiagnosticsDisplay = DiagnosticsDisplay(),
    launchSummary: String? = nil,
    onChange: @escaping (SettingsValues) -> Void
  ) {
    let model = SettingsModel(values: values, onChange: onChange)
    let display = UpdateCheckDisplay()
    let visibleHeight = NSScreen.main?.visibleFrame.height ?? Self.maximumContentHeight
    let contentHeight = Self.contentHeight(visibleHeight: visibleHeight)
    self.init(
      contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: contentHeight),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    settingsModel = model
    checkDisplay = display
    diagnosticsDisplay = diagnostics
    // Held strongly by the delegate; releasing on close would dangle that reference.
    isReleasedWhenClosed = false
    title = "Lanterna Settings"
    appearance = appearanceMode.nsAppearance
    let tabs = NSTabViewController()
    tabs.tabStyle = .toolbar
    tabs.canPropagateSelectedChildViewControllerTitle = false
    let missing = MissingPermission.list(for: permissionState)
    let generalHost = NSHostingController(rootView: AnyView(GeneralTabRoot(
      model: model,
      checkDisplay: display,
      version: version,
      launchSummary: launchSummary,
      missing: missing,
      opener: opener,
      onCheckNow: onCheckNow,
      diagnostics: diagnostics
    )))
    generalHost.preferredContentSize = NSSize(width: Self.contentWidth, height: contentHeight)
    generalHost.sizingOptions = []
    let appearanceHost = NSHostingController(rootView: AnyView(SettingsTabRoot(
      model: model,
      content: { SettingsAppearanceView(values: $0) }
    )))
    appearanceHost.preferredContentSize = NSSize(width: Self.contentWidth, height: contentHeight)
    appearanceHost.sizingOptions = []
    let filterHost = NSHostingController(rootView: AnyView(SettingsTabRoot(
      model: model,
      content: { SettingsFilterView(values: $0) }
    )))
    filterHost.preferredContentSize = NSSize(width: Self.contentWidth, height: contentHeight)
    filterHost.sizingOptions = []
    let groupsHost = NSHostingController(rootView: AnyView(SettingsTabRoot(
      model: model,
      content: { SettingsGroupsView(values: $0) }
    )))
    groupsHost.preferredContentSize = NSSize(width: Self.contentWidth, height: contentHeight)
    groupsHost.sizingOptions = []
    let keyboardHost = NSHostingController(rootView: AnyView(SettingsTabRoot(
      model: model,
      content: { SettingsKeyboardView(values: $0) }
    )))
    keyboardHost.preferredContentSize = NSSize(width: Self.contentWidth, height: contentHeight)
    keyboardHost.sizingOptions = []
    let hosts: [NSHostingController<AnyView>] = [generalHost, appearanceHost, filterHost, groupsHost, keyboardHost]
    for (tab, host) in zip(SettingsTab.allCases, hosts) {
      let item = NSTabViewItem(viewController: host)
      item.label = tab.title
      item.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.title)
      tabs.addTabViewItem(item)
    }
    contentViewController = tabs
    center()
  }

  // MARK: Internal

  /// The fixed content width shared by every tab.
  static let contentWidth: CGFloat = 640

  /// The tallest content the window ever shows.
  static let maximumContentHeight: CGFloat = 600

  /// The chrome above the content, used to fit low screens.
  static let chromeHeight: CGFloat = 80

  /// The shared values behind every tab, held strongly here.
  private(set) var settingsModel = SettingsModel(values: .defaults, onChange: { _ in })

  /// What the General tab shows about the last manual check.
  ///
  /// Held here so reopening the window starts unconfirmed again.
  private(set) var checkDisplay = UpdateCheckDisplay()

  /// What the Diagnostics section shows, refreshed by the delegate.
  private(set) var diagnosticsDisplay = DiagnosticsDisplay()

  /// The content height for a screen's visible height: the maximum, or
  /// less when the visible height minus the chrome is shorter.
  static func contentHeight(visibleHeight: CGFloat) -> CGFloat {
    min(maximumContentHeight, visibleHeight - chromeHeight)
  }

}

// MARK: - GeneralTabRoot

/// The General tab root, observing the shared model and the check display.
struct GeneralTabRoot: View {
  @ObservedObject var model: SettingsModel
  @ObservedObject var checkDisplay: UpdateCheckDisplay

  let version: DisplayedVersion
  let launchSummary: String?
  let missing: [MissingPermission]
  let opener: SettingsOpener
  let onCheckNow: () -> Void
  let diagnostics: DiagnosticsDisplay

  var body: some View {
    SettingsGeneralView(
      values: $model.values,
      version: version,
      launchSummary: launchSummary,
      missing: missing,
      opener: opener,
      checkResultText: checkDisplay.resultText,
      isChecking: checkDisplay.isChecking,
      onCheckNow: onCheckNow,
      diagnostics: diagnostics
    )
  }
}

// MARK: - SettingsTabRoot

/// A tab root that forwards the shared values to its content.
struct SettingsTabRoot<Content: View>: View {
  @ObservedObject var model: SettingsModel

  let content: (Binding<SettingsValues>) -> Content

  var body: some View {
    content($model.values)
  }
}
