//
//  StatBadgeView.swift
//  Un badge de stat du HUD : icône + valeur (avec fraction max optionnelle),
//  pulsation rouge quand la valeur passe sous un seuil critique, et popover
//  explicatif au tap. Extrait de `ContentView.swift` pour lisibilité.
//

import SwiftUI

// MARK: - Une stat du HUD (icône + valeur, avec pulsation si critique)

struct StatBadge: View {
    let icon: String
    let value: Int
    let max: Int
    let color: Color
    /// Si la valeur descend à ce seuil (ou en dessous), la stat pulse pour
    /// alerter le joueur. `nil` = pas d'alerte (ex. Habileté).
    let criticalThreshold: Int?
    let accessibility: String
    /// True = afficher la fraction `value/max`. False = juste `value`
    /// (utile pour l'Habileté où current et max sont toujours égaux —
    /// les bonus permanents montent les deux, jamais l'un sans l'autre,
    /// donc la fraction est du bruit).
    var showsMax: Bool = true

    @State private var pulse: Bool = false
    /// Différence du dernier changement de valeur, pour afficher un
    /// floater +N / -N qui s'envole. Reset à nil après l'animation.
    @State private var delta: Int? = nil
    @State private var deltaToken: UUID = UUID()
    /// Tap sur un badge → popover explicatif (« Habileté : ta dextérité au
    /// combat, ajoutée à chaque jet d'attaque… »). Aide les nouveaux
    /// joueurs à comprendre ce que représente chaque chiffre sans avoir
    /// à fouiller dans une page d'aide.
    @State private var showsTooltip: Bool = false

    private var isCritical: Bool {
        guard let threshold = criticalThreshold else { return false }
        return value <= threshold && value > 0
    }

    /// Valeur affichée, clampée à 0 pour éviter les chiffres négatifs
    /// (cas typique : on subit 4 dégâts à 2 PV, stamina passe à -2 avant
    /// que le moteur déclenche la mort → le HUD affichait "-2" pendant
    /// une frame). Le calcul du critical et la mort restent basés sur
    /// la vraie `value`, seul l'affichage est clampé.
    private var displayValue: Int { Swift.max(0, value) }

    var body: some View {
        VStack(spacing: 2) {
            StatGlyph(icon: icon, color: color.opacity(0.75), size: 11)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(displayValue)")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(color)
                if showsMax {
                    Text("/\(max)")
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .foregroundColor(Theme.inkFaded)
                }
            }
        }
        .frame(minWidth: 38)
        .opacity(isCritical && pulse ? 0.55 : 1.0)
        .scaleEffect(isCritical && pulse ? 0.96 : 1.0)
        // Floater +N / -N animé au-dessus du badge quand la stat varie.
        .overlay(alignment: .top) {
            if let d = delta {
                Text(d > 0 ? "+\(d)" : "\(d)")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundColor(d > 0 ? Theme.oldGold : Theme.blood)
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
            // Disparition différée du floater au bout d'1.1 s.
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

    /// Stat sémantique déduite de l'icône — l'icône est notre source de
    /// vérité pour `ability` / `life` / `luck`. Permet de rendre le
    /// tooltip indépendant du label d'accessibilité (qui pourrait être
    /// localisé un jour).
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

/// Trois stats principales exposées dans le HUD. Sert à router le tooltip
/// vers le bon texte.
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

    /// Phrase ramassée : ce que la stat MESURE.
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

    /// Explication plus longue : comment la stat est utilisée et ce qui la fait varier.
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

/// Carte parchemin affichée en popover quand le joueur tape un
/// `StatBadge`. Titre + icône colorée, résumé en italique, puis détail
/// en corps plus discret.
private struct StatTooltipCard: View {
    let stat: StatTooltipKind
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatGlyph(icon: stat.icon, color: accent, size: 14)
                Text(stat.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
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
