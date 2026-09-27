import SwiftUI

/// The Filter tab: which windows reach the switcher list.
///
/// One picker per special window kind. Each offers the same three
/// placements; absent keys mean the defaults the pickers show. Future
/// filtering options (exclusion lists, grouping) join this tab.
struct SettingsFilterView: View {
    @Binding var values: SettingsValues

    var body: some View {
        Form {
            Picker("Windows on other spaces", selection: $values.displayModes.otherSpace) {
                Text("Show").tag(DisplayMode.show)
                Text("Hide").tag(DisplayMode.hide)
                Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
            }
            Picker("Windows of hidden apps", selection: $values.displayModes.hiddenApp) {
                Text("Show").tag(DisplayMode.show)
                Text("Hide").tag(DisplayMode.hide)
                Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
            }
            Picker("Minimized windows", selection: $values.displayModes.minimized) {
                Text("Show").tag(DisplayMode.show)
                Text("Hide").tag(DisplayMode.hide)
                Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
            }
            Picker("Fullscreen windows", selection: $values.displayModes.fullscreen) {
                Text("Show").tag(DisplayMode.show)
                Text("Hide").tag(DisplayMode.hide)
                Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
            }
            Picker("Romaji matching", selection: $values.romajiScope) {
                Text("Kana only").tag(RomajiScope.kanaOnly)
                Text("Kana and kanji readings").tag(RomajiScope.kanaKanji)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
