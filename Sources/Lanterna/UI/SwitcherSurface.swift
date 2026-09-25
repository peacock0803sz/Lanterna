/// The panel as the code deciding when to show it sees it: something that can
/// be put up with a list, taken down, and asked whether it is up.
///
/// It is behind a protocol because a real panel needs a window server, which
/// a test process has no business asking for. Whether it is up is asked of the
/// panel rather than tracked alongside it: two records of one thing are two
/// things that can disagree.
///
/// Kept in a file of its own rather than beside the presenter that uses it.
/// This is the boundary letting the selection move has widened — keys, a
/// chosen row, and the panel being asked to redraw one are all here now —
/// and a boundary that grows belongs somewhere its growth is not charged to
/// a file that was already close to the length the linter allows.
@MainActor
protocol SwitcherSurface {
    var isPresented: Bool { get }

    /// Whether key presses are reaching the panel at this instant.
    var isTakingKeys: Bool { get }

    /// Puts the panel up showing this list, with this row drawn as chosen.
    ///
    /// **Takes no keys.** That is `takeKeys()`, and the separation is the
    /// most load-bearing thing in this protocol. The tests of the real panel
    /// put one on screen twice; were key status taken here, every run of the
    /// suite would pull the developer's typing into a panel nothing had shown
    /// them. Putting it behind an entry those tests do not call makes the
    /// guarantee structural. An argument saying whether to take keys would
    /// not: it would only turn "do not call the other method" into "do not
    /// pass true", which is the same thing to remember in a place where
    /// forgetting is quieter.
    func present(windows: [WindowItem], selecting: WindowItem.Identifier?)

    /// Asks for key presses, and answers whether they will arrive.
    ///
    /// The answer is the only notice a refusal gives, so it is not one a
    /// caller may drop by accident: a window that cannot become key says
    /// nothing, raises nothing, and goes on looking exactly like one that
    /// did. No `@discardableResult`, for that reason — a caller meaning to
    /// throw it away spells that out with `_ =` and says why, the way the
    /// deliberate discards in `AppDelegate` do.
    func takeKeys() -> Bool

    /// Redraws with a different row chosen, changing nothing else about the
    /// panel — not its size, not its position, and writing no line.
    func showSelection(_ id: WindowItem.Identifier?)

    /// Swaps the rows on screen for a narrowed set, redrawing the query
    /// beside them, and changes nothing else about the panel — not its size,
    /// not its position, and writing no line.
    func updateList(windows: [WindowItem], selecting: WindowItem.Identifier?, query: String)

    func dismiss()
}

extension SwitcherPanel: SwitcherSurface {}
