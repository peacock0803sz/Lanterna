import SwiftUI

/// One line of the switcher list: hint, application name, icon, window title.
struct WindowRow: View {
    let window: WindowItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(window.shortcutHint)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 24, alignment: .trailing)

            Text(window.appName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 110, alignment: .trailing)

            Image(nsImage: window.icon)
                .resizable()
                .frame(width: 18, height: 18)

            Text(window.windowTitle)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        // The fixed height is what keeps the panel-height formula exact.
        .frame(height: PanelMetrics.rowHeight)
        .background(selectionHighlight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var selectionHighlight: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.3))
        }
    }
}
