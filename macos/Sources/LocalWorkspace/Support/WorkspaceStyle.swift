import SwiftUI
import AppKit

/// Shared adaptive palette for native views and the embedded workbench.
enum WorkspacePalette {
    static func nsColor(_ token: String) -> NSColor {
        // Keep large surfaces native; color belongs to controls and state.
        let colors: [String: NSColor] = [
            "page": .windowBackgroundColor, "sidebar": .windowBackgroundColor,
            "surface": .controlBackgroundColor, "raised": .controlColor,
            "text": .labelColor, "secondary": .secondaryLabelColor,
            "border": .separatorColor, "selection": .unemphasizedSelectedContentBackgroundColor,
            "blue": .systemBlue, "button": .controlAccentColor, "teal": .systemTeal,
            "violet": .systemPurple, "orange": .systemOrange, "danger": .systemRed,
        ]
        return colors[token]!
    }
    static let page = Color(nsColor: nsColor("page"))
    static let sidebar = Color(nsColor: nsColor("sidebar"))
    static let surface = Color(nsColor: nsColor("surface"))
    static let raised = Color(nsColor: nsColor("raised"))
    static let text = Color(nsColor: nsColor("text"))
    static let secondaryText = Color(nsColor: nsColor("secondary"))
    static let border = Color(nsColor: nsColor("border"))
    static let blue = Color(nsColor: nsColor("blue"))
    static let button = Color(nsColor: nsColor("button"))
    static let teal = Color(nsColor: nsColor("teal"))
    static let violet = Color(nsColor: nsColor("violet"))
    static let orange = Color(nsColor: nsColor("orange"))
}

enum WorkspaceStyle {
    static let pagePadding: CGFloat = 28
    static let cardPadding: CGFloat = 20
    static let cornerRadius: CGFloat = 14
}

struct WorkspaceSymbol: View {
    let name: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.46, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
    }
}

struct WorkspaceCard<Content: View>: View {
    var padding: CGFloat = WorkspaceStyle.cardPadding
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspacePalette.surface, in: RoundedRectangle(cornerRadius: WorkspaceStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: WorkspaceStyle.cornerRadius)
                    .strokeBorder(WorkspacePalette.border, lineWidth: 1)
            }
    }
}

struct WorkspaceSettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            WorkspaceCard(padding: 18, content: content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkspacePreferenceRow: View {
    let title: String
    let description: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.medium))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
