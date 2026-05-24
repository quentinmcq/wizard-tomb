//
//  EndingsView.swift
//  « Tes aventures » — récap des fins déjà atteintes par le joueur, accessible
//  depuis le menu. Les fins non encore découvertes apparaissent grisées avec
//  un indice court. Données persistées via `GameSession.discoveredEndings`.
//

import SwiftUI

struct EndingsView: View {
    let discovered: Set<FinalOutcome>
    @Environment(\.dismiss) private var dismiss

    private var totalCount: Int { FinalOutcome.allCases.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground
                ScrollView {
                    VStack(spacing: 16) {
                        progressBanner
                        VStack(spacing: 12) {
                            ForEach(FinalOutcome.allCases, id: \.self) { outcome in
                                EndingRow(outcome: outcome,
                                          isDiscovered: discovered.contains(outcome))
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Tes aventures")
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
        let n = discovered.count
        let label: String = {
            switch n {
            case 0: return "Aucune issue encore connue. Le tombeau attend."
            case totalCount:
                return "Tu as vu chaque issue que le tombeau réserve. Cinquante ans à attendre — tu y as répondu en entier."
            default:
                return "\(n) / \(totalCount) issues découvertes."
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.display(12))
                .foregroundColor(Theme.inkFaded)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct EndingRow: View {
    let outcome: FinalOutcome
    let isDiscovered: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if isDiscovered {
                    // Issue trouvée → asset pixel-art `adventure_find`.
                    Theme.icon("adventure_find", size: 18, color: Theme.oldGold)
                } else {
                    // Placeholder pixel-art pour les fins non découvertes.
                    Theme.icon("question_mark", size: 18,
                               color: Theme.inkFaded.opacity(0.55))
                }
            }
            .frame(width: 24)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(isDiscovered ? outcome.title : "Issue inconnue")
                    .font(Theme.display(13))
                    .foregroundColor(isDiscovered ? Theme.ink : Theme.inkFaded)
                Text(isDiscovered ? outcome.blurb : outcome.hint)
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
                .fill(Theme.parchmentLight.opacity(isDiscovered ? 0.55 : 0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(isDiscovered ? 0.45 : 0.25),
                        lineWidth: 0.6)
        )
        .opacity(isDiscovered ? 1.0 : 0.75)
    }
}
