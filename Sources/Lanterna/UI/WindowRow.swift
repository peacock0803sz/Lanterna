import SwiftUI

/// One line of the switcher list: hint, application name, icon, window title.
///
/// The query travels with the row so the matches can be painted where they
/// are. Judging is not done here: the ranges come from the same pure
/// function the narrowing does, and this only paints what it is given.
struct WindowRow: View {

  // MARK: Internal

  let window: WindowItem
  let isSelected: Bool
  let query: String
  /// Whether subsequence queries match as well as substrings. Decides
  /// which ranges the highlight paints; judging is not done here.
  var fuzzy = true
  /// The text and icon scale step, handed down from the panel.
  var textScale = TextScaleLevel.standard
  /// Whether the row sits in a subgroup under a heading, whatever put it
  /// there. Such rows draw dimmed unless they are chosen.
  var isInSubgroup = false

  var body: some View {
    HStack(spacing: 12) {
      Text(window.shortcutHint)
        .font(.system(size: scaled(11), design: .monospaced))
        .foregroundStyle(hintTextStyle)
        .frame(width: scaled(30), alignment: .center)
        .background(hintBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 5)
            .stroke(hintBorder)
        )

      highlighted(
        window.appName,
        normal: AnyShapeStyle(.secondary),
        selected: AnyShapeStyle(Color.white.opacity(0.85))
      )
      .font(.system(size: scaled(14)))
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(width: scaled(96), alignment: .trailing)

      Image(nsImage: window.icon)
        .resizable()
        .frame(width: scaled(22), height: scaled(22))

      if window.isWindowless {
        // Matching reads the name column for this row, so the title
        // column only says there is no window to name.
        Text("No open windows")
          .font(.system(size: scaled(14)))
          .italic()
          .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
          .lineLimit(1)
      } else {
        highlighted(
          window.displayTitle,
          normal: AnyShapeStyle(.primary),
          selected: AnyShapeStyle(.white)
        )
        .font(.system(size: scaled(14)))
        .lineLimit(1)
        .truncationMode(.tail)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    // The fixed height is what keeps the panel-height formula exact.
    .frame(height: PanelMetrics.rowHeight(for: textScale))
    .background(selectionHighlight)
    .opacity(isInSubgroup && !isSelected ? 0.55 : 1)
  }

  // MARK: Private

  @Environment(\.colorScheme) private var colorScheme

  /// The hint frame fill, following the choice and the appearance.
  private var hintBackground: some ShapeStyle {
    if isSelected {
      AnyShapeStyle(Color.white.opacity(0.18))
    } else if colorScheme == .dark {
      AnyShapeStyle(Color.white.opacity(0.07))
    } else {
      AnyShapeStyle(Color.primary.opacity(0.04))
    }
  }

  /// The hint frame edge, following the choice and the appearance.
  private var hintBorder: some ShapeStyle {
    if isSelected {
      AnyShapeStyle(Color.white.opacity(0.25))
    } else if colorScheme == .dark {
      AnyShapeStyle(Color.white.opacity(0.1))
    } else {
      AnyShapeStyle(Color.primary.opacity(0.08))
    }
  }

  /// The hint wording, white on the chosen row and secondary elsewhere.
  private var hintTextStyle: AnyShapeStyle {
    isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary)
  }

  @ViewBuilder
  private var selectionHighlight: some View {
    if isSelected {
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.accentColor)
    }
  }

  /// One scaled point size: the base size times the step, in whole points.
  private func scaled(_ base: Double) -> Double {
    (base * textScale.factor).rounded()
  }

  /// The style a run wears when it is not a match: the chosen style on
  /// the chosen row, the usual style everywhere else.
  private func rowStyle(normal: AnyShapeStyle, selected: AnyShapeStyle) -> AnyShapeStyle {
    isSelected ? selected : normal
  }

  /// The text with every match of the query in bold, wearing the row style
  /// throughout, chosen or otherwise.
  private func highlighted(
    _ text: String,
    normal: AnyShapeStyle,
    selected: AnyShapeStyle
  ) -> Text {
    let base = rowStyle(normal: normal, selected: selected)
    let ranges: [Range<String.Index>]
    if RomajiMatcher.engine.isOpen {
      ranges = WindowFilter.matchedRanges(query: query, in: text, engine: RomajiMatcher.engine)
    } else if fuzzy {
      let conventional = WindowFilter.matchedRanges(query: query, in: text)
      ranges = conventional.isEmpty ? WindowFilter.subsequenceRanges(query: query, in: text) : conventional
    } else {
      ranges = WindowFilter.matchedRanges(query: query, in: text)
    }
    guard !ranges.isEmpty else { return Text(text).foregroundStyle(base) }
    var out = Text("")
    var cursor = text.startIndex
    for range in ranges {
      let before = Text(String(text[cursor ..< range.lowerBound])).foregroundStyle(base)
      let hit = Text(String(text[range])).bold().foregroundStyle(base)
      out = Text("\(out)\(before)\(hit)")
      cursor = range.upperBound
    }
    let tail = Text(String(text[cursor...])).foregroundStyle(base)
    return Text("\(out)\(tail)")
  }

}
