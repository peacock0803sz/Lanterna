import SwiftUI

extension View {
    /// Applies the Liquid Glass panel surface.
    ///
    /// The glass shape is passed explicitly because the API defaults to a
    /// capsule, which is wrong for a panel-sized surface. The content is
    /// clipped before the glass is applied, so the glass itself is not cut.
    /// No shadow is drawn here, because Liquid Glass supplies its own.
    func adaptiveGlass(cornerRadius: CGFloat = 12) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
