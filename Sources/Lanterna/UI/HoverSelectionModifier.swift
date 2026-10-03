import AppKit
import SwiftUI

/// The hover-to-select tracking on one window row.
///
/// Off attaches nothing: the row behaves exactly as before, with no
/// tracking area of its own. On reports the row the pointer moved onto,
/// dropping arrivals where the pointer sat when the appearance opened,
/// so opening under the pointer leaves the opening choice alone.
/// Headings and empty lines never carry this: only window rows do.
struct HoverSelectionModifier: ViewModifier {
  /// The row this tracking belongs to.
  var id: WindowItem.Identifier
  /// Whether the hover switch is on.
  var enabled: Bool
  /// The pointer position the appearance opened with.
  var anchor: HoverAnchor?
  /// Where a counted hover goes.
  var onHoverRow: ((WindowItem.Identifier) -> Void)?

  func body(content: Content) -> some View {
    if enabled {
      content.onHover { hovering in
        guard hovering, let receive = onHoverRow else { return }
        if let anchor, NSEvent.mouseLocation == anchor.point {
          return
        }
        receive(id)
      }
    } else {
      content
    }
  }
}
