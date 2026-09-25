import SwiftUI

/// One line of the switcher list: hint, application name, icon, window title.
///
/// The query travels with the row so the matches can be painted where they
/// are. Judging is not done here: the ranges come from the same pure
/// function the narrowing does, and this only paints what it is given.
struct WindowRow: View {
    let window: WindowItem
    let isSelected: Bool
    let query: String

    var body: some View {
        HStack(spacing: 8) {
            Text(window.shortcutHint)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(rowStyle(AnyShapeStyle(.tertiary)))
                .frame(width: 24, alignment: .trailing)

            highlighted(window.appName, base: AnyShapeStyle(.secondary))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 110, alignment: .trailing)

            Image(nsImage: window.icon)
                .resizable()
                .frame(width: 18, height: 18)

            highlighted(window.displayTitle, base: AnyShapeStyle(.primary))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        // The fixed height is what keeps the panel-height formula exact.
        .frame(height: PanelMetrics.rowHeight)
        .background(selectionHighlight)
    }

    /// The style a run wears when it is not a match: white on the chosen
    /// row, the usual style everywhere else.
    private func rowStyle(_ normal: AnyShapeStyle) -> AnyShapeStyle {
        isSelected ? AnyShapeStyle(.white) : normal
    }

    /// The text with every match of the query in red. The chosen row stays
    /// all white: red on blue is unreadable, and the choice is already said
    /// by the fill.
    private func highlighted(_ text: String, base: AnyShapeStyle) -> Text {
        let plain = Text(text).foregroundStyle(rowStyle(base))
        guard !isSelected else { return plain }
        let ranges = WindowFilter.matchedRanges(query: query, in: text)
        guard !ranges.isEmpty else { return plain }
        var out = Text("")
        var cursor = text.startIndex
        for range in ranges {
            out = out + Text(String(text[cursor ..< range.lowerBound])).foregroundStyle(rowStyle(base))
                + Text(String(text[range])).foregroundColor(.red)
            cursor = range.upperBound
        }
        return out + Text(String(text[cursor...])).foregroundStyle(rowStyle(base))
    }

    @ViewBuilder
    private var selectionHighlight: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor)
        }
    }
}
