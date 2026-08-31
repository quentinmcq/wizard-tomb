import SwiftUI

// MARK: - Une stat du HUD (icône + valeur, avec pulsation si critique)

struct StatBadge: View {
    let icon: String
    let value: Int
    let max: Int
    let color: Color
    let criticalThreshold: Int?
    let accessibility: String
    var showsMax: Bool = true

    @State private var pulse: Bool = false
    @State private var delta: Int? = nil
    @State private var deltaToken: UUID = UUID()
    @State private var showsTooltip: Bool = false

    private var isCritical: Bool {
        guard let threshold = criticalThreshold else { return false }
        return value <= threshold && value > 0
    }

    private var displayValue: Int { Swift.max(0, value) }

    var body: some View {
        VStack(spacing: 2) {
            StatGlyph(icon: icon, color: color.opacity(0.75), size: 11)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(displayValue)")
                    .font(Theme.serif(16, weight: .bold, maxScale: 1.3))
                    .foregroundColor(color)
                if showsMax {
                    Text("/\(max)")
                        .font(Theme.serif(10, maxScale: 1.3))
                        .foregroundColor(Theme.inkFaded)
                }
            }
        }
        .frame(minWidth: 38)
        .opacity(isCritical && pulse ? 0.55 : 1.0)
        .scaleEffect(isCritical && pulse ? 0.96 : 1.0)
        .overlay(alignment: .top) {
            if let d = delta {
                Text(d > 0 ? "+\(d)" : "\(d)")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundColor(d > 0 ? Theme.goldInk : Theme.blood)
                    .shadow(color: Theme.ink.opacity(0.4), radius: 2, x: 0, y: 1)
                    .id(deltaToken)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .offset(y: -12)
            }
        }
        .onAppear { syncPulse() }
        .onChange(of: isCritical) { _, _ in syncPulse() }
        .onChange(of: value) { oldValue, newValue in
            let diff = newValue - oldValue
            guard diff != 0 else { return }
            deltaToken = UUID()
            withAnimation(.easeOut(duration: 0.3)) {
                delta = diff
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                if delta == diff {
                    withAnimation(.easeIn(duration: 0.25)) {
                        delta = nil
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            showsMax
                ? "\(accessibility) \(displayValue) sur \(max)"
                : "\(accessibility) \(displayValue)"
        )
        .accessibilityHint("Appuie pour voir l'explication de la stat.")
        .contentShape(Rectangle())
        .onTapGesture { showsTooltip = true }
        .popover(isPresented: $showsTooltip, attachmentAnchor: .point(.top), arrowEdge: .top) {
            StatTooltipCard(stat: tooltipStat, accent: color)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Theme.parchmentLight)
        }
    }

    private var tooltipStat: StatTooltipKind {
        switch icon {
        case "ability": return .skill
        case "life":    return .stamina
        case "luck":    return .luck
        default:        return .skill
        }
    }

    private func syncPulse() {
        if isCritical {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                pulse = false
            }
        }
    }
}

// MARK: - Tooltip de stat (explication au tap)

enum StatTooltipKind {
    case skill, stamina, luck

    var title: String {
        switch self {
        case .skill:   return "Habileté"
        case .stamina: return "Endurance"
        case .luck:    return "Chance"
        }
    }

    var icon: String {
        switch self {
        case .skill:   return "ability"
        case .stamina: return "life"
        case .luck:    return "luck"
        }
    }

    var summary: String {
        switch self {
        case .skill:
            return "Ta dextérité au combat."
        case .stamina:
            return "Ce qui te tient debout."
        case .luck:
            return "Le sourire des dieux."
        }
    }

    var detail: String {
        switch self {
        case .skill:
            return "Ajoutée à chaque jet d'attaque (2d6 + Habileté). Plus elle est haute, plus tu touches souvent et plus tu pares bien. Certaines armes la majorent — un crochet bien aiguisé, une lame magique, etc."
        case .stamina:
            return "Tes points de vie. Tombe à 0 et l'aventure s'arrête. Tu en perds en encaissant des coups ou des pièges, tu en récupères en buvant des potions, en mangeant ou en passant la nuit dans un lit chaud."
        case .luck:
            return "Pour tenter ta Chance : tu lances 2d6 et tu dois faire ≤ Chance. Réussir double un coup, amortit un dégât, déjoue un piège. Chaque tentative t'en coûte 1 point — utilise-la quand ça compte."
        }
    }
}

private struct StatTooltipCard: View {
    let stat: StatTooltipKind
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatGlyph(icon: stat.icon, color: accent, size: 14)
                Text(stat.title)
                    .font(Theme.serif(16, weight: .semibold))
                    .foregroundColor(Theme.ink)
            }
            Text(stat.summary)
                .font(Theme.body(13))
                .italic()
                .foregroundColor(Theme.inkFaded)
            Rectangle()
                .fill(Theme.inkFaded.opacity(0.3))
                .frame(height: 0.5)
            Text(stat.detail)
                .font(Theme.body(13))
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
    }
}
