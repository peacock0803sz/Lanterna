import SwiftUI

extension View {
    /// Applies the panel surface for the running OS: Liquid Glass on macOS 26,
    /// a blurred material on macOS 15.
    ///
    /// The glass shape is passed explicitly because the API defaults to a
    /// capsule, which is wrong for a panel-sized surface. Both branches clip
    /// the content to the same rounded rectangle, so list rows cannot square
    /// off the corners, and both clip before the surface is applied so the
    /// surface itself is not cut. No shadow is drawn here: on macOS 15 the
    /// window shadow comes from AppKit in `SwitcherPanel`, and on macOS 26
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
