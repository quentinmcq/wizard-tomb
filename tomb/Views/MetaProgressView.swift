import SwiftUI

// MARK: - Écran

struct MetaListScreen<Item: Hashable, Row: View>: View {
    let title: String
    let progressLabel: String
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground
                ScrollView {
                    VStack(spacing: 16) {
                        progressBanner
                        VStack(spacing: 12) {
                            ForEach(items, id: \.self) { item in
                                row(item)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(Theme.ink)
                }
            }
        }
    }

    private var progressBanner: some View {
        Text(progressLabel)
            .font(Theme.display(12))
            .foregroundColor(Theme.inkFaded)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .parchmentCard()
    }
}

// MARK: - Ligne

struct MetaRow<Icon: View, Content: View>: View {
    let isRevealed: Bool
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon()
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .parchmentCard(fill: isRevealed ? 0.55 : 0.30,
                       stroke: isRevealed ? 0.45 : 0.25,
                       lineWidth: 0.6)
        .opacity(isRevealed ? 1.0 : 0.75)
    }
}

struct MetaRowTitle: View {
    let text: String
    let isRevealed: Bool

    var body: some View {
        Text(text)
            .font(Theme.display(13))
            .foregroundColor(isRevealed ? Theme.ink : Theme.inkFaded)
    }
}

struct MetaRowBody: View {
    let text: String
    var dimmed: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.body(13))
            .italic()
            .foregroundColor(dimmed ? Theme.inkFaded.opacity(0.7) : Theme.inkFaded)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
