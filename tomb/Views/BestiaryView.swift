import SwiftUI

struct BestiaryView: View {
    let defeated: Set<String>

    private var orderedIds: [String] { EnemyCatalog.bestiaryOrder }

    var body: some View {
        MetaListScreen(title: "Bestiaire",
                       progressLabel: progressLabel,
                       items: orderedIds) { id in
            BestiaryRow(enemyId: id, isDefeated: defeated.contains(id))
        }
    }

    private var progressLabel: String {
        let known = orderedIds.filter { defeated.contains($0) }.count
        guard known > 0 else {
            return "Aucune créature consignée. Les pages sont encore blanches."
        }
        return "\(known) / \(orderedIds.count) créatures consignées."
    }
}

private struct BestiaryRow: View {
    let enemyId: String
    let isDefeated: Bool

    @State private var showFullPortrait: Bool = false

    private var enemy: Enemy? { EnemyCatalog.all[enemyId] }
    private var lore: String { EnemyCatalog.lore[enemyId] ?? "" }

    var body: some View {
        MetaRow(isRevealed: isDefeated) {
            portrait
        } content: {
            MetaRowTitle(text: isDefeated ? (enemy?.name ?? "Créature inconnue")
                                          : "Créature inconnue",
                         isRevealed: isDefeated)
            if isDefeated, let enemy {
                if let subtitle = enemy.subtitle {
                    Text(subtitle)
                        .font(Theme.serif(11))
                        .italic()
                        .foregroundColor(Theme.inkFaded)
                }
                statsLine(enemy: enemy)
                MetaRowBody(text: lore)
            } else {
                MetaRowBody(
                    text: "Tu n'as encore croisé cette créature. Ou tu lui as échappé sans la regarder en face.",
                    dimmed: true
                )
            }
        }
        .fullScreenCover(isPresented: $showFullPortrait) {
            if let enemy {
                EnemyPortraitFullScreen(enemy: enemy)
            }
        }
    }

    @ViewBuilder
    private var portrait: some View {
        if let img = Theme.enemyPortrait(enemyId) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipped()
                .saturation(0)
                .colorMultiply(isDefeated ? Theme.parchmentLight : Theme.ink)
                .opacity(isDefeated ? 1.0 : 0.4)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Theme.inkFaded.opacity(0.5), lineWidth: 0.6)
                )
                .overlay(alignment: .topTrailing) {
                    if isDefeated {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.parchmentLight)
                            .padding(2)
                            .background(Circle().fill(Theme.ink.opacity(0.7)))
                            .offset(x: 4, y: -4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isDefeated { showFullPortrait = true }
                }
                .accessibilityAddTraits(isDefeated ? .isButton : [])
                .accessibilityLabel(
                    isDefeated
                        ? "Voir le portrait de \(enemy?.name ?? "la créature") en grand"
                        : "Portrait scellé"
                )
        } else {
            Group {
                if isDefeated {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.inkFaded.opacity(0.85))
                } else {
                    Theme.icon("question_mark", size: 22,
                               color: Theme.inkFaded.opacity(0.5))
                }
            }
            .frame(width: 56, height: 56)
        }
    }

    private func statsLine(enemy: Enemy) -> some View {
        HStack(spacing: 12) {
            statChip(label: "HAB", value: enemy.skill, color: Theme.inkBlue)
            statChip(label: "END", value: enemy.stamina, color: Theme.blood)
        }
    }

    private func statChip(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.display(9))
                .foregroundColor(Theme.inkFaded)
            Text("\(value)")
                .font(Theme.serif(13, weight: .bold))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 0.5)
        )
    }
}
