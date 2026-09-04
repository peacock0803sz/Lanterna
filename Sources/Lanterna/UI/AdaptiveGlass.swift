import SwiftUI

extension View {
    /// Applies the panel surface for the running OS: Liquid Glass on macOS 26,
    /// a blurred material on macOS 15.
    ///
    /// The glass shape is passed explicitly because the API defaults to a
    /// capsule, which is wrong for a panel-sized surface. Both branches clip to
    /// the same rounded rectangle so list content cannot square off the
    /// corners. The drop shadow is the window's, drawn by AppKit in
    /// `SwitcherPanel`.
    @ViewBuilder
    func adaptiveGlass(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
