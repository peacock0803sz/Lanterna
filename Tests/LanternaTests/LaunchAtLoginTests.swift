import Foundation
@testable import Lanterna
import ServiceManagement
import Testing

/// The seam the sync offers the tests: a login item that never touches
/// the machine, with scripted answers for every question the sync asks.
private struct FakeLoginItem: LoginItemControlling {
    var status: SMAppService.Status
    var registerError: Error?
    var unregisterError: Error?

    func register() throws {
        if let registerError {
            throw registerError
        }
    }

    func unregister() throws {
        if let unregisterError {
            throw unregisterError
        }
    }
}

private struct ProbeError: Error {}

struct LaunchAtLoginTests {
    private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
        AppConfiguration.decode(Data(text.utf8))
    }

    // MARK: - The setting in the file

    @Test func booleanValuesAreValid() throws {
        let enabled = try #require(decode("{\"version\": 1, \"launchAtLogin\": true}").successValue)
        #expect(enabled.config.launchAtLogin == true)
        let disabled = try #require(decode("{\"version\": 1, \"launchAtLogin\": false}").successValue)
        #expect(disabled.config.launchAtLogin == false)
    }

    @Test func absentMeansNil() throws {
        let decoded = try #require(decode("{\"version\": 1}").successValue)
        #expect(decoded.config.launchAtLogin == nil)
    }

    @Test func integersAreInvalid() {
        #expect(decode("{\"version\": 1, \"launchAtLogin\": 1}").failureValue != nil)
        #expect(decode("{\"version\": 1, \"launchAtLogin\": 0}").failureValue != nil)
    }

    @Test func stringsAreInvalid() {
        #expect(decode("{\"version\": 1, \"launchAtLogin\": \"on\"}").failureValue != nil)
    }

    @Test func encodedFormRoundTrips() throws {
        let data = AppConfiguration.encode(
            ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil, launchAtLogin: true)
        )
        let decoded = try #require(AppConfiguration.decode(data).successValue)
        #expect(decoded.config.launchAtLogin == true)
        let scaffold = AppConfiguration.encode(
            ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        )
        #expect(String(bytes: scaffold, encoding: .utf8) == AppConfiguration.scaffoldJSON)
    }

    @Test func settingsValuesRoundTrips() {
        let fromFile = SettingsValues.effective(from: ValidConfiguration(
            version: 1,
            sampleCount: nil,
            stopMonitorEverySeconds: nil,
            launchAtLogin: true
        ))
        #expect(fromFile.launchAtLogin == true)
        let back = fromFile.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        #expect(back.launchAtLogin == true)
        #expect(SettingsValues.defaults.launchAtLogin == false)
    }

    // MARK: - The decision table

    @Test func enabledStateStaysSilent() {
        #expect(LaunchAtLogin.action(desired: true, status: .enabled) == .none)
        #expect(LaunchAtLogin.action(desired: false, status: .notRegistered) == .none)
        #expect(LaunchAtLogin.action(desired: false, status: .notFound) == .none)
    }

    @Test func desiredOnRegisters() {
        #expect(LaunchAtLogin.action(desired: true, status: .notRegistered) == .register)
        #expect(LaunchAtLogin.action(desired: true, status: .notFound) == .register)
        #expect(LaunchAtLogin.action(desired: true, status: .requiresApproval) == .register)
    }

    @Test func desiredOffUnregisters() {
        #expect(LaunchAtLogin.action(desired: false, status: .enabled) == .unregister)
        #expect(LaunchAtLogin.action(desired: false, status: .requiresApproval) == .unregister)
    }

    // MARK: - The diagnostics lines

    @Test func changesLeaveOneLine() {
        let registered = LaunchAtLogin.sync(
            desired: true,
            service: FakeLoginItem(status: .notRegistered)
        )
        #expect(registered == "login item registered (launch at login is on)")
        let unregistered = LaunchAtLogin.sync(
            desired: false,
            service: FakeLoginItem(status: .enabled)
        )
        #expect(unregistered == "login item unregistered (launch at login is off)")
    }

    @Test func quietRunsStaySilent() {
        #expect(LaunchAtLogin.sync(desired: true, service: FakeLoginItem(status: .enabled)) == nil)
        #expect(LaunchAtLogin.sync(desired: false, service: FakeLoginItem(status: .notRegistered)) == nil)
        #expect(LaunchAtLogin.sync(desired: false, service: nil) == nil)
    }

    @Test func failuresExplainThemselves() {
        let failed = LaunchAtLogin.sync(
            desired: true,
            service: FakeLoginItem(status: .notRegistered, registerError: ProbeError())
        )
        #expect(failed?.contains("login item unchanged (register failed: ") == true)
        #expect(failed?.contains("(launch at login is on)") == true)
        let unregistered = LaunchAtLogin.sync(
            desired: false,
            service: FakeLoginItem(status: .enabled, unregisterError: ProbeError())
        )
        #expect(unregistered?.contains("login item unchanged (unregister failed: ") == true)
        #expect(unregistered?.contains("(launch at login is off)") == true)
        let unbundled = LaunchAtLogin.sync(desired: true, service: nil)
        #expect(unbundled == "login item unchanged (not a bundled app) (launch at login is on)")
    }
}
