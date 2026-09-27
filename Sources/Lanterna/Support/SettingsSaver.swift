import Foundation

/// What one save attempt found.
///
/// Kept apart from the write itself so the caller can ask first and show
/// a confirmation or a notice instead of writing blindly.
enum SettingsSaveOutcome: Equatable, Sendable {
    /// The file now holds the given settings.
    case saved
    /// The file on disk is invalid; saving would throw away a hand edit.
    /// The caller asks the user first and saves again with approval.
    case needsConfirmation
    /// The write failed; the file is untouched and the run keeps its values.
    case failed(reason: String)
}

/// Decides whether a save may go ahead and carries it out.
///
/// Reads the file on disk rather than trusting a remembered verdict, so a
/// hand edit landing between opening the settings and saving still gets
/// its confirmation.
enum SettingsSaver {
    /// Saves the settings, asking first when the disk file is invalid.
    ///
    /// A missing file is created. An invalid file is left alone unless
    /// `replacingInvalidFile` carries the user's approval. A failure
    /// reports its reason and never leaves a half-written file, because
    /// the write underneath is atomic.
    static func save(
        _ config: ValidConfiguration,
        to url: URL,
        replacingInvalidFile: Bool
    ) -> SettingsSaveOutcome {
        if !replacingInvalidFile, isInvalidFile(at: url) {
            return .needsConfirmation
        }
        do {
            try AppConfiguration.save(config, to: url)
            return .saved
        } catch {
            return .failed(reason: "cannot write file")
        }
    }

    /// Whether the file exists and fails validation.
    ///
    /// A missing file is not invalid: it simply has nothing to throw away.
    private static func isInvalidFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let data = try? Data(contentsOf: url) else { return true }
        if case .failure = AppConfiguration.decode(data) {
            return true
        }
        return false
    }
}
