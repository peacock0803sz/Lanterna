import Foundation

/// The matcher the panel reads while it is up.
///
/// Opened once at launch (see `main.swift`), read-only afterwards.
/// Every panel path (choice, drawing, height, highlight) reads this
/// one engine, so a query narrows and highlights the same rows
/// everywhere. A closed engine means a broken install; callers fall
/// back to the legacy matching then.
///
/// Shared as `nonisolated(unsafe)`: writes happen once, ahead of the
/// run loop, and every later access reads. Tests build their own
/// engines instead of touching this one.
enum RomajiMatcher {
    /// The shared engine. Tests build their own engines instead.
    nonisolated(unsafe) static var engine = MigemoEngine()

    /// Opens the shared engine for one run.
    ///
    /// With the kanji scope the dictionary beside the config file backs
    /// matching; otherwise, or when the file is missing or broken, only
    /// kana readings match. Returns whether a valid dictionary backs
    /// the engine, so the launch path can say why kanji stays out.
    @discardableResult
    static func open(
        scope: RomajiScope,
        dictionaryDirectory: URL?,
        tableDirectory: URL?
    ) -> Bool {
        let engine = MigemoEngine()
        let dictionaryPath: String?
        if scope == .kanaKanji, let dictionaryDirectory {
            dictionaryPath = dictionaryDirectory
                .appendingPathComponent("migemo-dict", isDirectory: false).path
        } else {
            dictionaryPath = nil
        }
        guard let tables = tableDirectory,
              engine.open(dictionaryPath: dictionaryPath, tableDirectory: tables.path)
        else {
            self.engine = MigemoEngine()
            return false
        }
        self.engine = engine
        return engine.dictionaryActive
    }
}
