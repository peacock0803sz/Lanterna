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
  func toolbarTabsFollowFixedOrder() {
    let controller = tabController()
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

  /// The title stays put while tabs change underneath.
  @Test
  func titleStaysPut() {
    #expect(makeWindow().title == "Lanterna Settings")
  }

  /// The content height follows the visible height through one pure function.
  @Test
  func contentHeightFollowsVisibleHeight() {
    #expect(SettingsWindow.contentHeight(visibleHeight: 1000) == 600)
    #expect(SettingsWindow.contentHeight(visibleHeight: 600) == 520)
  }

  // MARK: Private

  private func makeWindow() -> SettingsWindow {
    SettingsWindow(
      values: SettingsValues.defaults,
      version: DisplayedVersion(full: "0.0.0"),
      permissionState: PermissionState(accessibilityGranted: false, inputMonitoringGranted: false),
      opener: { _ in false },
      onChange: { _ in }
    )
  }

  private func tabController() -> NSTabViewController {
    let controller = makeWindow().contentViewController as? NSTabViewController
    return controller!
  }

}
