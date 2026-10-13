import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore

    var body: some View {
        Form {
            Section {
                themeRow(.standard)
            } footer: {
                Text("The first piece in each pair moves first.")
            }
            Section("Holidays") {
                ForEach(BoardTheme.holidays) { themeRow($0) }
            }
            Section("Everyday") {
                ForEach(BoardTheme.everyday) { themeRow($0) }
            }
        }
        .navigationTitle("Themes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func themeRow(_ theme: BoardTheme) -> some View {
        let selected = preferences.theme == theme
        return Button {
            preferences.theme = theme
        } label: {
            HStack(spacing: 14) {
                ThemeBoardPreview(theme: theme)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(theme.pieceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title), \(theme.pieceDescription)")
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityIdentifier("theme-option-\(theme.rawValue)")
    }
}

private struct ThemeBoardPreview: View {
    let theme: BoardTheme
    @Environment(\.colorScheme) private var colorScheme

    private static let sampleBoard: [CellState] = {
        var board = [CellState](repeating: .empty, count: 25)
        board[6] = .black
        board[12] = .white
        board[13] = .black
        board[17] = .white
        return board
    }()

    var body: some View {
        let palette = GomokuPalette.resolve(colorScheme, theme: theme)
        Canvas { context, size in
            BoardDrawing.draw(
                context: &context, size: size,
                board: Self.sampleBoard, boardSize: 5,
                lastMove: nil, winningLine: [], hint: nil, preview: nil, cursor: nil,
                palette: palette
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.boardEdge, lineWidth: 1)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
