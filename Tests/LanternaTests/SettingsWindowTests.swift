import AppKit
@testable import Lanterna
import SwiftUI
import Testing

// MARK: - SettingsWindowTests

/// What the settings window shows first and writes back.
///
/// The window itself opens like the other informational windows; these
/// cover the values underneath: present keys win, absent keys mean the
/// defaults, and a save round trip keeps both the shown values and the
/// hidden debug keys.
@MainActor
struct SettingsWindowTests {
  @Test
  func effectiveValuesFollowPresentKeys() {
    var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    config.appearanceMode = .dark
    config.minimizedMode = .hide
    config.romajiScope = .kanaOnly
    let values = SettingsValues.effective(from: config)
    #expect(values.appearanceMode == .dark)
    #expect(values.displayModes.minimized == .hide)
    #expect(values.displayModes.otherSpace == .show)
    #expect(values.romajiScope == .kanaOnly)
  }

  @Test
  func defaultsMatchFileDefaults() {
    #expect(SettingsValues.defaults.appearanceMode == .system)
    #expect(SettingsValues.defaults.displayModes == DisplayModes.defaults)
    #expect(SettingsValues.defaults.romajiScope == .kanaKanji)
  }

  @Test
  func romajiScopeDefaultsToKanji() {
    let config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(SettingsValues.effective(from: config).romajiScope == .kanaKanji)
  }

  @Test
  func romajiScopeFollowsPresentKey() {
    var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    config.romajiScope = .kanaOnly
    #expect(SettingsValues.effective(from: config).romajiScope == .kanaOnly)
    let saved = SettingsValues.effective(from: config)
      .configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(saved.romajiScope == .kanaOnly)
  }

  @Test
  func configurationRoundTripKeepsShownAndHiddenKeys() {
    var values = SettingsValues.defaults
    values.appearanceMode = .light
    values.displayModes.fullscreen = .hide
    values.romajiScope = .kanaOnly
    let config = values.configuration(version: 1, sampleCount: 3, stopMonitorEverySeconds: 7)
    #expect(config.appearanceMode == .light)
    #expect(config.fullscreenMode == .hide)
    #expect(config.romajiScope == .kanaOnly)
    #expect(config.sampleCount == 3)
    #expect(config.stopMonitorEverySeconds == 7)
    let decoded = AppConfiguration.decode(AppConfiguration.encode(config))
    #expect(decoded.successValue?.config == config)
  }
}

extension SettingsWindowTests {

  // MARK: Internal

  /// The frame keeps toolbar tabs in a fixed order with stable titles.
  @Test
  func toolbarTabsFollowFixedOrder() throws {
    let controller = try tabController()
    #expect(controller.tabStyle == .toolbar)
    #expect(controller.tabViewItems.map(\.label) == ["General", "Appearance", "Filter", "Keyboard"])
  }

  /// Every tab shares one content size, so switching tabs never resizes.
  @Test
  func everyTabSharesOneContentSize() {
    let window = makeWindow()
    window.layoutIfNeeded()
    let controller = window.contentViewController as? NSTabViewController
    let hosts = controller?.tabViewItems.compactMap { $0.viewController as? NSHostingController<AnyView> }
    #expect(hosts?.count == 4)
    let sizes = hosts?.map(\.preferredContentSize) ?? []
    #expect(Set(sizes.map(\.width)).count == 1)
    #expect(Set(sizes.map(\.height)).count == 1)
    #expect(sizes.first?.width == SettingsWindow.contentWidth)
    for host in hosts ?? [] {
      #expect(host.sizingOptions == [])
    }
  }

  /// The title stays put when another tab is chosen, even one whose
  /// content carries a title of its own: the tab controller never takes
  /// up the chosen child's title.
  @Test
  func titleStaysPut() throws {
    let window = makeWindow()
    let controller = try #require(window.contentViewController as? NSTabViewController)
    for item in controller.tabViewItems {
      item.viewController?.title = item.label
    }
    for index in controller.tabViewItems.indices.reversed() {
      controller.selectedTabViewItemIndex = index
      #expect(controller.title == nil)
      #expect(window.title == "Lanterna Settings")
    }
  }

  /// A change to the window's shared model reaches the caller's handler once.
  @Test
  func modelChangeReachesCallerOnce() {
    var reports = [SettingsValues]()
    let window = makeWindow(onChange: { reports.append($0) })
    var changed = SettingsValues.defaults
    changed.appearanceMode = .dark
    window.settingsModel.values = changed
    #expect(reports == [changed])
  }

  /// The content height follows the visible height through one pure function.
  @Test
  func contentHeightFollowsVisibleHeight() {
    #expect(SettingsWindow.contentHeight(visibleHeight: 1000) == 600)
    #expect(SettingsWindow.contentHeight(visibleHeight: 600) == 520)
  }

  // MARK: Private

  private func makeWindow(onChange: @escaping (SettingsValues) -> Void = { _ in }) -> SettingsWindow {
    SettingsWindow(
      values: SettingsValues.defaults,
      version: DisplayedVersion(full: "0.0.0"),
      permissionState: PermissionState(accessibilityGranted: false, inputMonitoringGranted: false),
      opener: { _ in false },
      onChange: onChange
    )
  }

  private func tabController() throws -> NSTabViewController {
    try #require(makeWindow().contentViewController as? NSTabViewController)
  }

}
