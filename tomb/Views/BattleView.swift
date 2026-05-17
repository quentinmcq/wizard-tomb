//
//  BattleView.swift
//  UI du combat tour par tour. Animations de dés sur Attaquer et Tenter
//  sa Chance : les rolls sont pré-tirés, affichés en animation pendant
//  ~700ms, puis injectés dans le BattleEngine pour exécuter l'action.
//

import SwiftUI

struct BattleView: View {
    @Binding var battle: BattleState
    @Binding var player: PlayerState
    let onEnd: (BattleOutcome) -> Void

    @State private var pendingRoll: PendingDiceRoll? = nil
    /// True pendant que l'animation des dés joue. Cache la barre d'actions
    /// pour éviter qu'un tap interrompe le roll en cours. Une fois à false,
    /// les boutons reviennent SANS effacer le pendingRoll (les valeurs des
    /// dés restent à l'écran jusqu'à la prochaine action).
    @State private var isRolling: Bool = false

    /// Durée totale de l'animation des dés (chute + rotation + bounce).
    private let rollMs = 1600

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EnemyCard(enemy: battle.enemy)
            if !battle.log.isEmpty {
                BattleLog(entries: battle.log)
            }
            actionArea
        }
    }

    // MARK: - Zone d'actions (dés + boutons côte à côte)

    private var actionArea: some View {
        VStack(spacing: 14) {
            if let pendingRoll {
                DiceRollOverlay(roll: pendingRoll, durationMs: rollMs)
                    .id(pendingRoll.id)
                    .transition(.opacity)
            }
            if !isRolling {
                actionBar
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isRolling)
        .animation(.easeInOut(duration: 0.2), value: pendingRoll?.id)
    }

    @ViewBuilder
    private var actionBar: some View {
        switch battle.phase {
        case .awaitingAction:
            HStack(spacing: 10) {
                BattleActionButton(label: "Attaquer",
                                   icon: "burst.fill",
                                   tint: Theme.blood) {
                    performAttack()
                }
                // Bouton "Tenter de fuir" disponible seulement si le knot
                // l'autorise ET si on n'a pas déjà tenté : une seule chance
                // par combat, échec ou réussite.
                if battle.fleeTarget != nil && !battle.fleeUsed {
                    BattleActionButton(label: "Tenter de fuir",
                                       icon: "figure.run",
                                       tint: Theme.inkFaded) {
                        performFlee()
                    }
                }
            }

        case .canTryLuckOffense:
            luckPrompt(prompt: "Tenter ta Chance pour redoubler ton coup ?",
                       offensive: true)

        case .canTryLuckDefense:
            luckPrompt(prompt: "Tenter ta Chance pour amortir le coup ?",
                       offensive: false)

        case .ended(let outcome):
            BattleActionButton(label: outcomeLabel(outcome),
                               icon: "chevron.right",
                               tint: Theme.ink) {
                onEnd(outcome)
            }
        }
    }

    private func outcomeLabel(_ outcome: BattleOutcome) -> String {
        switch outcome {
        case .victory: return "Continuer"
        case .defeat:  return "Voir l'épitaphe"
        case .fled:    return "Reprendre ton souffle"
        }
    }

    private func luckPrompt(prompt: String, offensive: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "die.face.6.fill")
                    .foregroundColor(Theme.oldGold)
                Text(prompt)
                    .font(Theme.margin(13))
                    .italic()
                    .foregroundColor(Theme.inkFaded)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                BattleActionButton(label: "Tenter (Chance \(player.luck))",
                                   icon: "sparkles",
                                   tint: Theme.oldGold) {
                    performLuck(offensive: offensive)
                }
                BattleActionButton(label: "Attaquer",
                                   icon: "burst.fill",
                                   tint: Theme.blood) {
                    mutateBattle { BattleEngine.skipLuck(state: &$0) }
                    performAttack()
                }
            }
        }
    }

    // MARK: - Actions avec animation de dés

    private func performAttack() {
        let p1 = Int.random(in: 1...6)
        let p2 = Int.random(in: 1...6)
        let e1 = Int.random(in: 1...6)
        let e2 = Int.random(in: 1...6)

        AmbientAudio.shared.play(.diceRoll)
        isRolling = true

        withAnimation(.easeInOut(duration: 0.15)) {
            pendingRoll = PendingDiceRoll(
                kind: .attack(
                    playerDice: (p1, p2), playerSkill: player.skill,
                    enemyDice: (e1, e2),  enemySkill: battle.enemy.skill
                )
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(rollMs + 500)) {
            let playerStaminaBefore = player.stamina
            let enemyStaminaBefore  = battle.enemy.stamina

            withAnimation(.easeOut(duration: 0.25)) {
                mutateBattleAndPlayer { c, p in
                    BattleEngine.attack(
                        state: &c,
                        player: &p,
                        playerRoll: p1 + p2,
                        enemyRoll: e1 + e2
                    )
                }
            }
            isRolling = false

            if battle.enemy.stamina < enemyStaminaBefore {
                AmbientAudio.shared.play(.hitDealt)
            } else if player.stamina < playerStaminaBefore {
                AmbientAudio.shared.play(.takeHit)
            }
            // Râle final juste après l'impact qui termine l'ennemi, avant le
            // bouton "Continuer". Court délai pour ne pas se superposer au
            // hitDealt qui vient de jouer.
            if case .ended(.victory) = battle.phase {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) {
                    AmbientAudio.shared.play(.enemyDie)
                }
            }
            if case .ended(.defeat) = battle.phase {
                AmbientAudio.shared.play(.death)
            }
        }
    }

    private func performFlee() {
        let d1 = Int.random(in: 1...6)
        let d2 = Int.random(in: 1...6)

        AmbientAudio.shared.play(.diceRoll)
        isRolling = true

        withAnimation(.easeInOut(duration: 0.15)) {
            pendingRoll = PendingDiceRoll(kind: .luck(dice: (d1, d2)))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(rollMs + 500)) {
            let playerStaminaBefore = player.stamina

            withAnimation(.easeOut(duration: 0.25)) {
                mutateBattleAndPlayer { c, p in
                    BattleEngine.flee(state: &c, player: &p, luckRoll: d1 + d2)
                }
            }
            isRolling = false

            if case .ended(.fled) = battle.phase {
                AmbientAudio.shared.play(.lucky)
            } else if player.stamina < playerStaminaBefore {
                AmbientAudio.shared.play(.takeHit)
                if case .ended(.defeat) = battle.phase {
                    AmbientAudio.shared.play(.death)
                }
            }
        }
    }

    private func performLuck(offensive: Bool) {
        let d1 = Int.random(in: 1...6)
        let d2 = Int.random(in: 1...6)

        AmbientAudio.shared.play(.diceRoll)
        isRolling = true

        withAnimation(.easeInOut(duration: 0.15)) {
            pendingRoll = PendingDiceRoll(kind: .luck(dice: (d1, d2)))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(rollMs + 500)) {
            withAnimation(.easeOut(duration: 0.25)) {
                mutateBattleAndPlayer { c, p in
                    if offensive {
                        BattleEngine.tryLuckOffense(state: &c, player: &p, luckRoll: d1 + d2)
                    } else {
                        BattleEngine.tryLuckDefense(state: &c, player: &p, luckRoll: d1 + d2)
                    }
                }
            }
            isRolling = false

            if let last = battle.log.last {
                switch last.kind {
                case .lucky:   AmbientAudio.shared.play(.lucky)
                case .unlucky: AmbientAudio.shared.play(.unlucky)
                default: break
                }
            }
            // Mort de l'ennemi via test de Chance offensif (rare mais
            // possible : un coup chanceux pousse la jauge à 0).
            if case .ended(.victory) = battle.phase {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) {
                    AmbientAudio.shared.play(.enemyDie)
                }
            }
        }
    }

    // MARK: - Helpers pour passer @Binding en inout

    private func mutateBattle(_ block: (inout BattleState) -> Void) {
        var c = battle
        block(&c)
        battle = c
    }

    private func mutateBattleAndPlayer(_ block: (inout BattleState, inout PlayerState) -> Void) {
        var c = battle
        var p = player
        block(&c, &p)
        battle = c
        player = p
    }
}

// MARK: - Carte de l'ennemi

struct EnemyCard: View {
    let enemy: Enemy

    @State private var shakeOffset: CGFloat = 0
    @State private var lastStamina: Int = -1
    @State private var flash: Bool = false

    private var endRatio: Double {
        guard enemy.staminaMax > 0 else { return 0 }
        return Double(max(enemy.stamina, 0)) / Double(enemy.staminaMax)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(enemy.name)
                .font(Theme.display(15))
                .foregroundColor(Theme.ink)

            HStack(spacing: 22) {
                stat("Habileté", enemy.skill, Theme.inkBlue)
                stat("Endurance", max(enemy.stamina, 0), Theme.blood)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.parchmentDark.opacity(0.5))
                    Capsule()
                        .fill(Theme.blood.opacity(0.85))
                        .frame(width: geo.size.width * endRatio)
                        .animation(.easeOut(duration: 0.5), value: endRatio)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .leatherFrame(tint: Theme.blood)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.blood.opacity(flash ? 0.18 : 0))
        )
        .offset(x: shakeOffset)
        .onAppear { lastStamina = enemy.stamina }
        .onChange(of: enemy.stamina) { oldValue, newValue in
            if newValue < oldValue { triggerHit() }
            lastStamina = newValue
        }
    }

    private func triggerHit() {
        // Flash rouge bref
        withAnimation(.easeOut(duration: 0.12)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeIn(duration: 0.25)) { flash = false }
        }
        // Shake horizontal (sprint d'aller-retours)
        let amplitudes: [(CGFloat, Double)] = [
            (-8, 0.05), (8, 0.05),
            (-5, 0.05), (5, 0.05),
            (0,  0.05)
        ]
        var delay: Double = 0
        for (amp, dur) in amplitudes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: dur)) { shakeOffset = amp }
            }
            delay += dur
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(Theme.display(10))
                .foregroundColor(Theme.inkFaded)
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(color)
        }
    }

    // Le portrait du monstre a migré vers une planche pleine page affichée
    // AVANT le combat (cf. `pendingIllustration` posé par GameSession quand
    // le tag `# combat: <id>` est détecté). La carte combat reste épurée :
    // nom, stats, jauge d'Endurance.
}

// MARK: - Journal de combat

struct BattleLog: View {
    let entries: [BattleLogEntry]

    private var recent: [BattleLogEntry] {
        Array(entries.suffix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(recent) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol(for: entry.kind))
                        .foregroundColor(color(for: entry.kind))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, alignment: .center)
                    Text(entry.text)
                        .font(Theme.body(14))
                        .foregroundColor(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                    Spacer(minLength: 0)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(0.4), lineWidth: 0.6)
        )
    }

    private func symbol(for kind: BattleLogEntry.Kind) -> String {
        switch kind {
        case .info:     return "info.circle.fill"
        case .hitDealt: return "burst.fill"
        case .hitTaken: return "shield.slash.fill"
        case .miss:     return "shield.fill"
        case .lucky:    return "sparkles"
        case .unlucky:  return "exclamationmark.triangle.fill"
        case .end:      return "checkmark.seal.fill"
        }
    }

    private func color(for kind: BattleLogEntry.Kind) -> Color {
        switch kind {
        case .info:     return Theme.inkFaded
        case .hitDealt: return Theme.inkBlue
        case .hitTaken: return Theme.blood
        case .miss:     return Theme.inkFaded
        case .lucky:    return Theme.oldGold
        case .unlucky:  return Theme.blood
        case .end:      return Theme.ink
        }
    }
}

// MARK: - Bouton d'action de combat

struct BattleActionButton: View {
    let label: String
    let icon: String?
    let tint: Color
    let action: () -> Void

    init(label: String, icon: String? = nil, tint: Color, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(label)
                    .font(Theme.display(12))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(BattleButtonStyle(tint: tint))
    }
}

struct BattleButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .foregroundColor(Theme.parchmentLight)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 1.0 : 0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.ink.opacity(0.7), lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}
