import SwiftUI

struct EndingsView: View {
    let discovered: Set<FinalOutcome>

    var body: some View {
        MetaListScreen(title: "Tes aventures",
                       progressLabel: progressLabel,
                       items: FinalOutcome.allCases) { outcome in
            EndingRow(outcome: outcome,
                      isDiscovered: discovered.contains(outcome))
        }
    }

    private var progressLabel: String {
        let n = discovered.count
        let total = FinalOutcome.allCases.count
        switch n {
        case 0:
            return "Aucune issue encore connue. Le tombeau attend."
        case total:
            return "Tu as vu chaque issue que le tombeau réserve. Cinquante ans à attendre — tu y as répondu en entier."
        default:
            return "\(n) / \(total) issues découvertes."
        }
    }
}

private struct EndingRow: View {
    let outcome: FinalOutcome
    let isDiscovered: Bool

    var body: some View {
        MetaRow(isRevealed: isDiscovered) {
            Group {
                if isDiscovered {
                    Theme.icon("adventure_find", size: 18, color: Theme.goldInk)
                } else {
                    Theme.icon("question_mark", size: 18,
                               color: Theme.inkFaded.opacity(0.55))
                }
            }
            .frame(width: 24)
        } content: {
            MetaRowTitle(text: isDiscovered ? outcome.title : "Issue inconnue",
                         isRevealed: isDiscovered)
            MetaRowBody(text: isDiscovered ? outcome.blurb : outcome.hint)
        }
    }
}
