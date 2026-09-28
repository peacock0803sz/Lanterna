import Foundation

/// One optional key at a time, split out when the decoding file reached
/// the file-length limit. The shape of the file stays in `AppConfiguration`;
/// everything that reads a single key lives here.
extension AppConfiguration {
    /// Reads the on-off and channel keys together, so the assembly stays small.
    static func checkedSwitches(
        _ dict: [String: Any],
        into config: inout ValidConfiguration
    ) -> Result<Void, ConfigDecodeError> {
        switch checkedOptionalBool(dict, key: "launchAtLogin") {
        case let .success(found):
            config.launchAtLogin = found
        case let .failure(error):
            return .failure(error)
        }
        switch checkedOptionalBool(dict, key: "updateCheckEnabled") {
        case let .success(found):
            config.updateCheckEnabled = found
        case let .failure(error):
            return .failure(error)
        }
        switch checkedOptionalChannel(dict, key: "updateChannel") {
        case let .success(found):
            config.updateChannel = found
        case let .failure(error):
            return .failure(error)
        }
        return .success(())
    }

    /// Reads one optional integer key with its lower bound.
    static func checkedOptionalInt(
        _ dict: [String: Any],
        key: String,
        minimum: Int
    ) -> Result<Int?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let value = jsonInt(rawValue), value >= minimum else {
            return .failure(.invalidValue(key: key))
        }
        return .success(value)
    }

    /// Reads the count keys together, so `decode` stays small.
    static func checkedCountOptions(_ dict: [String: Any]) -> Result<
        (Int?, Int?), ConfigDecodeError
    > {
        let sampleCount: Int?
        switch checkedOptionalInt(dict, key: "sampleCount", minimum: 0) {
        case let .success(found):
            sampleCount = found
        case let .failure(error):
            return .failure(error)
        }
        let stopMonitorEvery: Int?
        switch checkedOptionalInt(dict, key: "stopMonitorEvery", minimum: 1) {
        case let .success(found):
            stopMonitorEvery = found
        case let .failure(error):
            return .failure(error)
        }
        return .success((sampleCount, stopMonitorEvery))
    }

    /// Reads one optional boolean key. Only a real boolean counts:
    /// integers are refused the way booleans are refused for integers.
    static func checkedOptionalBool(
        _ dict: [String: Any],
        key: String
    ) -> Result<Bool?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let number = rawValue as? NSNumber,
              String(cString: number.objCType) == "c"
        else {
            return .failure(.invalidValue(key: key))
        }
        return .success(number.boolValue)
    }

    /// Reads one optional display-mode key. Anything but a `DisplayMode`
    /// word invalidates the whole file, like any other bad value.
    static func checkedOptionalMode(
        _ dict: [String: Any],
        key: String
    ) -> Result<DisplayMode?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String, let mode = DisplayMode(rawValue: text) else {
            return .failure(.invalidValue(key: key))
        }
        return .success(mode)
    }

    /// Reads the optional appearance-mode key. Anything but an
    /// `AppearanceMode` word invalidates the whole file, like any other
    /// bad value.
    static func checkedOptionalAppearance(
        _ dict: [String: Any],
        key: String
    ) -> Result<AppearanceMode?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String, let mode = AppearanceMode(rawValue: text) else {
            return .failure(.invalidValue(key: key))
        }
        return .success(mode)
    }

    /// Reads the optional romaji-scope key. Anything but a
    /// `RomajiScope` word invalidates the whole file, like any other
    /// bad value.
    static func checkedOptionalRomajiScope(
        _ dict: [String: Any],
        key: String
    ) -> Result<RomajiScope?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String, let scope = RomajiScope(rawValue: text) else {
            return .failure(.invalidValue(key: key))
        }
        return .success(scope)
    }

    /// Reads one optional channel key. Only the two known words count:
    /// anything else invalidates the whole file, like any other bad value.
    static func checkedOptionalChannel(
        _ dict: [String: Any],
        key: String
    ) -> Result<String?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String,
              text == "stable" || text == "beta"
        else {
            return .failure(.invalidValue(key: key))
        }
        return .success(text)
    }

    /// A JSON integer and nothing else.
    ///
    /// Booleans are refused by their Objective-C type: an `is Bool` check
    /// wrongly matches integer 1, so only the `c` type is turned away.
    static func jsonInt(_ value: Any) -> Int? {
        if let number = value as? NSNumber, String(cString: number.objCType) == "c" {
            return nil
        }
        return value as? Int
    }
}
