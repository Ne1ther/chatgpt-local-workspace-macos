import SwiftUI

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
            .background(.background, in: RoundedRectangle(cornerRadius: WorkspaceStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: WorkspaceStyle.cornerRadius)
                    .strokeBorder(.quaternary, lineWidth: 1)
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
