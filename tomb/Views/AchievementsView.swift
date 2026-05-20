//
//  AchievementsView.swift
//  « Hauts faits » — récap des achievements débloqués au fil des parties.
//  Mêmes codes visuels que EndingsView / BestiaryView : sceau or pour ceux
//  obtenus, ? + indice pour les autres. Persisté via
//  `GameSession.unlockedAchievements`.
//

import SwiftUI

struct AchievementsView: View {
    let unlocked: Set<String>
    @Environment(\.dismiss) private var dismiss

    private var totalCount: Int { AchievementsCatalog.all.count }
    private var knownCount: Int {
        AchievementsCatalog.all.filter { unlocked.contains($0.id) }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground
                ScrollView {
                    VStack(spacing: 16) {
                        progressBanner
                        VStack(spacing: 12) {
                            ForEach(AchievementsCatalog.all) { ach in
                                AchievementRow(
                                    achievement: ach,
                                    isUnlocked: unlocked.contains(ach.id)
                                )
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Hauts faits")
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
        Text(knownCount == 0
             ? "Aucun haut fait à inscrire pour l'instant. Le tombeau garde ses secrets."
             : "\(knownCount) / \(totalCount) hauts faits réalisés.")
            .font(Theme.display(12))
            .foregroundColor(Theme.inkFaded)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.parchmentLight.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.inkFaded.opacity(0.45), lineWidth: 0.8)
            )
    }
}

private struct AchievementRow: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isUnlocked
                          ? Theme.oldGold.opacity(0.18)
                          : Theme.inkFaded.opacity(0.10))
                    .frame(width: 38, height: 38)
                if isUnlocked {
                    // Icône débloquée : SF Symbol ou asset pixel-art selon
                    // ce qu'a déclaré le catalogue d'achievements.
                    Theme.icon(achievement.icon, size: 16, color: Theme.oldGold)
                } else {
                    // Placeholder pixel-art commun à tous les hauts faits
                    // scellés.
                    Theme.icon("question_mark", size: 16,
                               color: Theme.inkFaded.opacity(0.55))
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(isUnlocked ? achievement.title : "Haut fait scellé")
                    .font(Theme.display(13))
                    .foregroundColor(isUnlocked ? Theme.ink : Theme.inkFaded)
                Text(isUnlocked ? achievement.description : achievement.hint)
                    .font(Theme.body(13))
                    .italic()
                    .foregroundColor(Theme.inkFaded)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.parchmentLight.opacity(isUnlocked ? 0.55 : 0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(isUnlocked ? 0.45 : 0.25),
                        lineWidth: 0.6)
        )
        .opacity(isUnlocked ? 1.0 : 0.75)
    }
}
