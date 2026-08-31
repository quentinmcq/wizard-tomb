import SwiftUI

struct AchievementsView: View {
    let unlocked: Set<String>

    var body: some View {
        MetaListScreen(title: "Hauts faits",
                       progressLabel: progressLabel,
                       items: AchievementsCatalog.all) { ach in
            AchievementRow(achievement: ach,
                           isUnlocked: unlocked.contains(ach.id))
        }
    }

    private var progressLabel: String {
        let known = AchievementsCatalog.all.filter { unlocked.contains($0.id) }.count
        guard known > 0 else {
            return "Aucun haut fait à inscrire pour l'instant. Le tombeau garde ses secrets."
        }
        return "\(known) / \(AchievementsCatalog.all.count) hauts faits réalisés."
    }
}

private struct AchievementRow: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        MetaRow(isRevealed: isUnlocked) {
            ZStack {
                Circle()
                    .fill(isUnlocked
                          ? Theme.oldGold.opacity(0.18)
                          : Theme.inkFaded.opacity(0.10))
                    .frame(width: 38, height: 38)
                if isUnlocked {
                    Theme.icon(achievement.icon, size: 16, color: Theme.goldInk)
                } else {
                    Theme.icon("question_mark", size: 16,
                               color: Theme.inkFaded.opacity(0.55))
                }
            }
        } content: {
            MetaRowTitle(text: isUnlocked ? achievement.title : "Haut fait scellé",
                         isRevealed: isUnlocked)
            MetaRowBody(text: isUnlocked ? achievement.description : achievement.hint)
        }
    }
}
