/// The recent-use evidence a show line carries, or nothing when the caller
/// has none to give.
///
/// The first row drawn and where the newest surviving record came from. Both
/// ride the line that already exists: the show line is the only place the
/// order of an appearance is ever written down, and a second line for it
/// would break the alternating count of shown and hidden lines. The presenter
/// always passes one (wired when the ordering landed); the tests that pin
/// other segments pass none and read the line they always read.
///
/// A file of its own because the measurements file it would have joined is
/// already long enough that adding to it would put it over the file limit.
struct MRUSummary: Equatable, Sendable {
    /// The first row drawn, or nothing when the list is empty. An unrecorded
    /// but non-empty list still names its actual first row: the row is drawn
    /// whether or not any use was ever recorded.
    let firstID: WindowItem.Identifier?
    /// Where the newest surviving record came from, judged after the sweep.
    /// Independent of which row is first.
    let source: MRUTracker.NewestSource

    /// The words the show line appends. An empty list names no first row;
    /// anything else names the row it drew and where the order came from.
    var phrase: String {
        let sourceWord: String
        switch source {
        case .commit:
            sourceWord = "commit"
        case .external:
            sourceWord = "external"
        case .none:
            sourceWord = "none"
        }
        guard let firstID else {
            return "mru first none via none"
        }
        return "mru first (window \(firstID.windowID)) via \(sourceWord)"
    }
}
