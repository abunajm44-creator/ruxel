import SwiftUI

// ToolStripView — horizontally scrolling strip of the 19 retouch tools.
// What: RTL order (brush first on the right); tap selects the tool panel.
// Inputs-outputs: selected tool binding; taps update EditorViewModel.
// Threading: SwiftUI view code; runs on the main actor.
struct ToolStripView: View {
    @Binding var selectedTool: EditorTool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EditorTool.allCases) { tool in
                    Button(action: { selectedTool = tool }) {
                        VStack(spacing: 4) {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 20))
                            Text(tool.titleKey)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(width: 64, height: 56)
                    }
                    .adaptiveGlass(
                        in: RoundedRectangle(cornerRadius: 14),
                        tint: selectedTool == tool ? Color.accentColor.opacity(0.25) : nil,
                        interactive: true
                    )
                    .foregroundStyle(selectedTool == tool ? .primary : .secondary)
                    .accessibilityLabel(Text(tool.titleKey))
                }
            }
            .padding(.horizontal, 12)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
