@testable import Lanterna
import Testing

struct AppearanceModeTests {
    private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
        AppConfiguration.decode(Data(text.utf8))
    }

    @Test func appearanceModeIsAbsentByDefault() throws {
        let decoded = try #require(decode("{\"version\": 1}").successValue)
        #expect(decoded.config.appearanceMode == nil)
    }

    @Test func appearanceModeDecodesWhenPresent() throws {
        for mode in [AppearanceMode.system, .light, .dark] {
            let decoded = try #require(
                decode("{\"version\": 1, \"appearanceMode\": \"\(mode.rawValue)\"}").successValue
            )
            #expect(decoded.config.appearanceMode == mode)
        }
    }

    @Test func invalidAppearanceModeFallsBackAsAWhole() {
        let cases: [(String, ConfigDecodeError)] = [
            ("{\"version\": 1, \"appearanceMode\": \"SYSTEM\"}", .invalidValue(key: "appearanceMode")),
            ("{\"version\": 1, \"appearanceMode\": \"followSystem\"}", .invalidValue(key: "appearanceMode")),
            ("{\"version\": 1, \"appearanceMode\": 1}", .invalidValue(key: "appearanceMode")),
            ("{\"version\": 1, \"appearanceMode\": true}", .invalidValue(key: "appearanceMode")),
        ]
        for (text, expected) in cases {
            #expect(decode(text).failureValue == expected, "for \(text)")
        }
    }

    @Test func absentAppearanceModeMeansSystem() {
        let config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        #expect(AppearanceMode.effective(from: config) == .system)
    }

    @Test func presentAppearanceModeOverridesDefault() {
        var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        config.appearanceMode = .dark
        #expect(AppearanceMode.effective(from: config) == .dark)
    }
}
