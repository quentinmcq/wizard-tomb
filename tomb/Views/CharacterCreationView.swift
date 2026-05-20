//
//  CharacterCreationView.swift
//  Création de personnage en quatre temps : on lance d'abord les dés
//  d'Endurance, puis d'Habileté, puis de Chance, et on arrive sur la page
//  de difficulté qui récapitule le tirage. Pas de bouton « relancer » :
//  si le joueur veut d'autres dés, il recommence l'aventure.
//

import SwiftUI

struct CharacterCreationView: View {
    @ObservedObject var session: GameSession
    @ObservedObject var audio: AmbientAudio

    /// Étapes du tirage séquentiel.
    enum Phase {
        case stamina, skill, luck, difficulty
    }

    @State private var phase: Phase = .stamina

    /// Les dés sont conservés en l'état dans la vue tant que le joueur n'a pas
    /// validé la création — ils ne bougent plus une fois lancés.
    @State private var staminaDice: (Int, Int)? = nil
    @State private var skillDie: Int? = nil
    @State private var luckDie: Int? = nil

    /// Forces la recréation des `Dice3DView` quand on lance pour la première
    /// fois (l'animation ne rejoue jamais ensuite — pas de relance).
    @State private var rollGeneration: Int = 0

    /// Bascule à true une fois l'animation des dés terminée, comme dans le
    /// combat : on cache le total tant que les dés roulent, on le révèle
    /// d'un seul coup quand ils se posent.
    @State private var revealed: Bool = false

    /// Durée de l'animation des Dice3DView (alignée sur `durationMs` passé
    /// plus bas). On attend ce temps + un petit délai avant de révéler le
    /// total.
    private let diceDurationMs = 900

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            header
            Spacer(minLength: 8)
            content
                .padding(.horizontal, 4)
            Spacer(minLength: 8)
            actions
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("L'aventurier")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundColor(Theme.ink)
            Text(headerSubtitle)
                .font(Theme.body(14))
                .italic()
                .foregroundColor(Theme.inkFaded)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .lineSpacing(2)
                .lineLimit(3, reservesSpace: true)
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .stamina:
            return "Lance les dés d'Endurance. C'est ce qui te tient debout quand les coups pleuvent."
        case .skill:
            return "À toi de tirer ton Habileté. C'est ce qui guide ta lame quand l'instant t'échappe."
        case .luck:
            return "Termine par la Chance. C'est ce qui fait pencher le destin quand la raison ne suffit plus."
        case .difficulty:
            return "Voilà ce que les dés ont décidé. Choisis maintenant l'épreuve que tu veux affronter."
        }
    }

    // MARK: - Content (variable selon la phase)

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .stamina:
            rollPhaseCard(
                label: "Endurance",
                icon: "life",
                color: Theme.blood,
                baseBonus: 12,
                diceCount: 2,
                values: staminaDice.map { [$0.0, $0.1] },
                key: "stamina"
            )
        case .skill:
            rollPhaseCard(
                label: "Habileté",
                icon: "ability",
                color: Theme.inkBlue,
                baseBonus: 6,
                diceCount: 1,
                values: skillDie.map { [$0] },
                key: "skill"
            )
        case .luck:
            rollPhaseCard(
                label: "Chance",
                icon: "luck",
                color: Theme.verdigris,
                baseBonus: 6,
                diceCount: 1,
                values: luckDie.map { [$0] },
                key: "luck"
            )
        case .difficulty:
            difficultyRecap
        }
    }

    // MARK: - Carte de tirage (une stat, dés au centre)

    private func rollPhaseCard(label: String,
                                icon: String,
                                color: Color,
                                baseBonus: Int,
                                diceCount: Int,
                                values: [Int]?,
                                key: String) -> some View {
        let placeholderValues = Array(repeating: 1, count: diceCount)
        let displayValues = values ?? placeholderValues
        let diceSum = values?.reduce(0, +)
        let total = diceSum.map { $0 + baseBonus }

        return VStack(spacing: 18) {
            HStack(spacing: 10) {
                StatGlyph(icon: icon, color: color, size: 18)
                Text(label)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundColor(color)
            }

            HStack(spacing: 10) {
                ForEach(Array(displayValues.enumerated()), id: \.offset) { idx, die in
                    Dice3DView(value: die, tint: color, durationMs: 900)
                        .frame(width: 76, height: 76)
                        .opacity(values == nil ? 0.25 : 1.0)
                        .id("\(key)-\(idx)-\(rollGeneration)")
                }
            }

            VStack(spacing: 2) {
                Text("\(diceCount)d6 + \(baseBonus)")
                    .font(.system(size: 11, design: .serif))
                    .foregroundColor(Theme.inkFaded)
                if let total, let diceSum, revealed {
                    Text("\(diceSum) + \(baseBonus) = \(total)")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(color)
                        .monospacedDigit()
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Text("— + \(baseBonus) = —")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(Theme.inkFaded.opacity(0.5))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(0.45), lineWidth: 0.8)
        )
    }

    // MARK: - Récapitulatif + difficulté

    private var difficultyRecap: some View {
        VStack(spacing: 14) {
            difficultyBanner
            if let roll = session.characterRoll {
                statLine(label: "Endurance",
                         icon: "life",
                         color: Theme.blood,
                         diceValues: [roll.staminaDice.0, roll.staminaDice.1],
                         baseBonus: 12,
                         penalty: roll.difficulty.statPenalty,
                         total: roll.stamina,
                         key: "stamina-recap")
                divider
                statLine(label: "Habileté",
                         icon: "ability",
                         color: Theme.inkBlue,
                         diceValues: [roll.skillDie],
                         baseBonus: 6,
                         penalty: roll.difficulty.statPenalty,
                         total: roll.skill,
                         key: "skill-recap")
                divider
                statLine(label: "Chance",
                         icon: "luck",
                         color: Theme.verdigris,
                         diceValues: [roll.luckDie],
                         baseBonus: 6,
                         penalty: roll.difficulty.statPenalty,
                         total: roll.luck,
                         key: "luck-recap")
            }
            difficultyPicker
                .padding(.top, 4)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(0.45), lineWidth: 0.8)
        )
    }

    private var difficultyPicker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Difficulty.allCases, id: \.self) { d in
                    Button {
                        session.setDifficulty(d)
                    } label: {
                        Text(d.title)
                            .font(Theme.display(11))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DifficultyButtonStyle(selected: session.difficulty == d))
                }
            }
            Text(session.difficulty.blurb)
                .font(Theme.body(12))
                .italic()
                .foregroundColor(Theme.inkFaded)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .padding(.horizontal, 8)
        }
    }

    private var difficultyBanner: some View {
        let hasPenalty = session.difficulty.statPenalty != 0
        let icon = hasPenalty ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
        let tint: Color = hasPenalty ? Theme.blood : Theme.inkFaded
        let text: String = {
            if hasPenalty {
                return "\(session.difficulty.title) : \(session.difficulty.statPenalty) sur chaque stat de départ"
            } else {
                return "\(session.difficulty.title) : tirage classique, aucune pénalité"
            }
        }()

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .font(.system(size: 12))
            Text(text)
                .font(Theme.display(11))
                .foregroundColor(tint)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 0.6)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.inkFaded.opacity(0.25))
            .frame(height: 0.6)
            .padding(.horizontal, 8)
    }

    private func statLine(label: String,
                          icon: String,
                          color: Color,
                          diceValues: [Int],
                          baseBonus: Int,
                          penalty: Int,
                          total: Int,
                          key: String) -> some View {
        let diceSum = diceValues.reduce(0, +)
        let penaltySegment = Text(penalty != 0 ? " − \(abs(penalty))" : "")
            .foregroundColor(penalty != 0 ? Theme.blood : Theme.inkFaded)

        return HStack(spacing: 12) {
            Label {
                Text(label)
                    .font(Theme.display(13))
                    .foregroundColor(color)
            } icon: {
                StatGlyph(icon: icon, color: color, size: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Array(diceValues.enumerated()), id: \.offset) { idx, die in
                    Dice3DView(value: die, tint: color, durationMs: 900)
                        .frame(width: 50, height: 50)
                        .id(key + "-\(idx)")
                }
            }

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(total)")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(color)
                    .monospacedDigit()
                Text("\(diceSum) + \(baseBonus)\(penaltySegment)")
                    .foregroundColor(Theme.inkFaded)
                    .font(.system(size: 10, design: .serif))
                    .monospacedDigit()
            }
            .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        // Le lien "Retour au menu" a été retiré : il ne servait pas à
        // grand-chose en cours de création (les jets ne sont pas encore
        // commités tant qu'on n'a pas validé la difficulté) et il
        // encombrait visuellement la page. `cancelCharacterCreation()`
        // reste disponible côté session pour les flows internes — juste
        // pas exposé via un bouton ici.
        primaryButton
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch phase {
        case .stamina:
            if staminaDice == nil {
                MenuPrimaryButton(label: "Lancer 2d6", icon: "die.face.6.fill") {
                    rollStamina()
                }
            } else if revealed {
                MenuPrimaryButton(label: "Continuer", icon: "chevron.right") {
                    phase = .skill
                    revealed = false
                }
                .transition(.opacity)
            }

        case .skill:
            if skillDie == nil {
                MenuPrimaryButton(label: "Lancer 1d6", icon: "die.face.6.fill") {
                    rollSkill()
                }
            } else if revealed {
                MenuPrimaryButton(label: "Continuer", icon: "chevron.right") {
                    phase = .luck
                    revealed = false
                }
                .transition(.opacity)
            }

        case .luck:
            if luckDie == nil {
                MenuPrimaryButton(label: "Lancer 1d6", icon: "die.face.6.fill") {
                    rollLuck()
                }
            } else if revealed {
                MenuPrimaryButton(label: "Continuer", icon: "chevron.right") {
                    finalizeRoll()
                    phase = .difficulty
                }
                .transition(.opacity)
            }

        case .difficulty:
            MenuPrimaryButton(label: "Commencer l'aventure", icon: "play.fill") {
                session.confirmCharacterAndStart()
            }
        }
    }

    // MARK: - Tirages

    private func rollStamina() {
        AmbientAudio.shared.play(.diceRoll)
        rollGeneration += 1
        revealed = false
        staminaDice = (Int.random(in: 1...6), Int.random(in: 1...6))
        scheduleReveal()
    }

    private func rollSkill() {
        AmbientAudio.shared.play(.diceRoll)
        rollGeneration += 1
        revealed = false
        skillDie = Int.random(in: 1...6)
        scheduleReveal()
    }

    private func rollLuck() {
        AmbientAudio.shared.play(.diceRoll)
        rollGeneration += 1
        revealed = false
        luckDie = Int.random(in: 1...6)
        scheduleReveal()
    }

    /// Aligne le moment où l'on dévoile le total sur la fin de l'animation
    /// des dés, comme la `DiceRollOverlay` du combat. Le bouton « Continuer »
    /// apparaît au même moment.
    private func scheduleReveal() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(diceDurationMs + 80))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                revealed = true
            }
        }
    }

    /// Pousse les trois dés vers la `GameSession` une fois la Chance lancée,
    /// avant d'afficher la page de difficulté. C'est cette étape qui crée le
    /// `characterRoll` consommé par `confirmCharacterAndStart`.
    private func finalizeRoll() {
        guard let staminaDice, let skillDie, let luckDie else { return }
        session.setCharacterRoll(
            skillDie: skillDie,
            staminaDice: staminaDice,
            luckDie: luckDie
        )
    }
}

// MARK: - Bouton segmenté de difficulté

struct DifficultyButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(selected ? Theme.parchmentLight : Theme.ink)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(selected
                          ? Theme.blood.opacity(configuration.isPressed ? 1.0 : 0.85)
                          : Theme.parchmentLight.opacity(configuration.isPressed ? 0.95 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(selected ? Theme.ink.opacity(0.6) : Theme.inkFaded.opacity(0.45),
                            lineWidth: selected ? 0.9 : 0.6)
            )
            .animation(.easeOut(duration: 0.15), value: selected)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}
