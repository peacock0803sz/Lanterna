@testable import Lanterna
import Testing

@MainActor
struct SettingsModelTests {
  @Test
  func changingOneFieldReportsTheWholeValueOnce() {
    var reported = [SettingsValues]()
    let model = SettingsModel(values: .defaults) { reported.append($0) }
    var next = SettingsValues.defaults
    next.launchAtLogin.toggle()
    model.values = next
    #expect(reported.count == 1)
    #expect(reported.first == next)
  }

  @Test
  func assigningTheSameValueReportsNothing() {
    var reported = 0
    let model = SettingsModel(values: .defaults) { _ in reported += 1 }
    model.values = SettingsValues.defaults
    #expect(reported == 0)
  }

  @Test
  func twoChangesReportTwiceWithTheLastValue() {
    var reported = [SettingsValues]()
    let model = SettingsModel(values: .defaults) { reported.append($0) }
    var first = SettingsValues.defaults
    first.launchAtLogin.toggle()
    model.values = first
    var second = first
    second.updateCheckEnabled.toggle()
    model.values = second
    #expect(reported.count == 2)
    #expect(reported.last == second)
  }
}
