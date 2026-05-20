//
//  BestiaryView.swift
//  « Bestiaire » — liste des créatures rencontrées au fil des parties.
//  Les ennemis non encore vaincus apparaissent en silhouette grisée, sans
//  leur nom ni leur paragraphe. Données persistées dans
//  `GameSession.defeatedEnemies`.
//

import SwiftUI

struct BestiaryView: View {
    let defeated: Set<String>
    @Environment(\.dismiss) private var dismiss

    /// Ordre stable d'affichage : on liste les ennemis tels qu'ils
    /// apparaissent dans l'aventure (village → forêt → marais → tombeau
    /// → aile sud → boss). Les phases intermédiaires de Mortimer sont
    /// regroupées sous l'entrée canonique pour ne pas spoiler.
    private static let orderedIds: [String] = [
        "goblin_scout",
        "forest_wolves",
        "forest_boar",
        "forest_lycanthrope",
        "marsh_serpent",
        "tomb_ghoul",
        "skeleton_guardians",
        "gallery_skeletons",
        "flooded_eels",
        "tomb_basilisk",
        "treasure_guardian",
        "vengeful_spirit",
        "pit_skeletons",
        "mortimer_spectre_phase1",
        "mortimer_spectre_phase2"
    ]

    private var totalCount: Int { Self.orderedIds.count }
    private var knownCount: Int {
        Self.orderedIds.filter { defeated.contains($0) }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground
                ScrollView {
                    VStack(spacing: 16) {
                        progressBanner
                        VStack(spacing: 12) {
                            ForEach(Self.orderedIds, id: \.self) { id in
                                BestiaryRow(enemyId: id,
                                            isDefeated: defeated.contains(id))
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Bestiaire")
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
             ? "Aucune créature consignée. Les pages sont encore blanches."
             : "\(knownCount) / \(totalCount) créatures consignées.")
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

private struct BestiaryRow: View {
    let enemyId: String
    let isDefeated: Bool

    private var enemy: Enemy? { EnemyCatalog.all[enemyId] }
    private var lore: String { EnemyCatalog.lore[enemyId] ?? "" }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            portrait
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(isDefeated ? (enemy?.name ?? "Créature inconnue") : "Créature inconnue")
                    .font(Theme.display(13))
                    .foregroundColor(isDefeated ? Theme.ink : Theme.inkFaded)
                if isDefeated, let enemy {
                    statsLine(enemy: enemy)
                    Text(lore)
                        .font(Theme.body(13))
                        .italic()
                        .foregroundColor(Theme.inkFaded)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Tu n'as encore croisé cette créature. Ou tu lui as échappé sans la regarder en face.")
                        .font(Theme.body(13))
                        .italic()
                        .foregroundColor(Theme.inkFaded.opacity(0.7))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.parchmentLight.opacity(isDefeated ? 0.55 : 0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(isDefeated ? 0.45 : 0.25),
                        lineWidth: 0.6)
        )
        .opacity(isDefeated ? 1.0 : 0.75)
    }

    /// Petit portrait de l'ennemi. Désaturé + teinté parchemin quand vaincu
    /// (s'intègre au cadre) ; silhouette noire opaque sinon. Si l'image
    /// n'est pas trouvée dans le bundle, on retombe sur un point d'interrogation.
    @ViewBuilder
    private var portrait: some View {
        if let img = Self.loadEnemyImage(enemyId: enemyId) {
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

    /// Cherche `<enemyId>.jpg` dans le bundle (convention historique des
    /// portraits d'ennemis), avec un fallback vers la racine de la version
    /// "base" si l'id contient un suffixe `_phaseN`.
    private static func loadEnemyImage(enemyId: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: enemyId, withExtension: "jpg"),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        if let range = enemyId.range(of: #"_phase\d+$"#, options: .regularExpression) {
            let base = String(enemyId[..<range.lowerBound])
            if let url = Bundle.main.url(forResource: base, withExtension: "jpg"),
               let img = UIImage(contentsOfFile: url.path) {
                return img
            }
        }
        return nil
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
                .font(.system(size: 13, weight: .bold, design: .serif))
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
