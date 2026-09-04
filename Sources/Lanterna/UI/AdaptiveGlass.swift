import SwiftUI

extension View {
    /// Applies the panel surface for the running OS: Liquid Glass on macOS 26,
    /// a blurred material on macOS 15.
    ///
    /// The glass shape is passed explicitly because the API defaults to a
    /// capsule, which is wrong for a panel-sized surface. Both branches use
    /// the same rounded rectangle, but it does different work in each: on
    /// macOS 26 the content is clipped before the glass is applied, so the
    /// glass itself is not cut, while on macOS 15 the material goes on first
    /// and the clip is what rounds it. No shadow is drawn here: on macOS 15
    /// the window shadow comes from AppKit in `SwitcherPanel`, and on macOS 26
    /// Liquid Glass supplies its own.
    @ViewBuilder
    func adaptiveGlass(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
