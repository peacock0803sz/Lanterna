import SwiftUI

extension View {
    /// Applies the panel surface for the running OS: Liquid Glass on macOS 26,
    /// a blurred material on macOS 15.
    ///
    /// The glass shape is passed explicitly because the API defaults to a
    /// capsule, which is wrong for a panel-sized surface.
    @ViewBuilder
    func adaptiveGlass(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }
}
