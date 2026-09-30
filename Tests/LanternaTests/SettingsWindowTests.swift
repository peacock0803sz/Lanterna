@testable import Lanterna
import Testing

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
