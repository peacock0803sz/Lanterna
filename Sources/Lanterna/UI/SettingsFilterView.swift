import SwiftUI

/// The Filter tab: which windows reach the switcher list.
///
/// One picker per special window kind, each with a note on what the
/// choices do. Future filtering options (exclusion lists, grouping)
/// join this tab.
struct SettingsFilterView: View {
    @Binding var values: SettingsValues

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("Windows on other spaces", selection: $values.displayModes.otherSpace) {
                    Text("Show").tag(DisplayMode.show)
                    Text("Hide").tag(DisplayMode.hide)
                    Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
                }
                Text("Windows living on another Space: mix them in, keep them out, or park them below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker("Windows of hidden apps", selection: $values.displayModes.hiddenApp) {
                    Text("Show").tag(DisplayMode.show)
                    Text("Hide").tag(DisplayMode.hide)
                    Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
                }
                Text("Windows of hidden applications: mix them in, keep them out, or park them below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker("Minimized windows", selection: $values.displayModes.minimized) {
                    Text("Show").tag(DisplayMode.show)
                    Text("Hide").tag(DisplayMode.hide)
                    Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
                }
                Text("Windows folded into the Dock: mix them in, keep them out, or park them below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker("Fullscreen windows", selection: $values.displayModes.fullscreen) {
                    Text("Show").tag(DisplayMode.show)
                    Text("Hide").tag(DisplayMode.hide)
                    Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
                }
                Text("Windows filling their own Space: mix them in, keep them out, or park them below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker("Romaji matching", selection: $values.romajiScope) {
                    Text("Kana only").tag(RomajiScope.kanaOnly)
                    Text("Kana and kanji readings").tag(RomajiScope.kanaKanji)
                }
                Text("Match kana readings only, or kanji readings too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
