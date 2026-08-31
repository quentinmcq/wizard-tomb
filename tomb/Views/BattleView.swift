import SwiftUI

struct BattleView: View {
    @Binding var battle: BattleState
    @Binding var player: PlayerState
    let onEnd: (BattleOutcome) -> Void
    var onOpenInventory: (() -> Void)? = nil

    @State private var pendingRoll: PendingDiceRoll? = nil
    @State private var isRolling: Bool = false
    @State private var currentRollMs: Int = 1600
    @State private var screenShake: CGFloat = 0
    @State private var showFleeConfirm: Bool = false
    @State private var pendingResolveWork: DispatchWorkItem? = nil
    @State private var revealRollEarly: Bool = false
    @State private var shakeTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rollMs = 1600

    private var hasUsableConsumable: Bool {
        player.items.contains { id in
            guard let effect = ItemCatalog.all[id]?.consumable else { return false }
            switch effect {
            case .heal:        return player.stamina < player.staminaMax
            case .restoreLuck: return player.luck < player.luckMax
            case .boostSkillNextAttack, .weakenEnemyNextAttack:
                return true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EnemyCard(enemy: battle.enemy)
            if !battle.log.isEmpty {
                BattleLog(entries: battle.log)
            }
            actionArea
        }
        .offset(x: screenShake)
        // ⚠️ Sans ça, quitter un combat pendant l'animation des dés (bouton
        // menu → « Oui ») laissait le `DispatchWorkItem` de résolution
        // s'exécuter ~2 s plus tard : il jouait le son d'impact et la
        // vibration PAR-DESSUS l'écran de menu, et réécrivait
        // `session.pendingBattle` via le binding — ressuscitant un combat
        // que `backToMenu()` venait d'effacer.
        .onDisappear {
            pendingResolveWork?.cancel()
            pendingResolveWork = nil
            shakeTask?.cancel()
            shakeTask = nil
            isRolling = false
        }
        .confirmationDialog(
            "Tenter de fuir ?",
            isPresented: $showFleeConfirm,
            titleVisibility: .visible
        ) {
            Button("Fuir (Test de Chance)", role: .destructive) {
                performFlee()
            }
            Button("Continuer le combat", role: .cancel) {}
        } message: {
            Text("Tu n'auras qu'une seule chance. Si tu échoues, \(battle.enemy.name) te frappera dans le dos.")
        }
    }

    // MARK: - #6 — Shake d'écran

    private func triggerScreenShake(intensity: CGFloat) {
        shakeTask?.cancel()
        shakeTask = Task { @MainActor in
            await Shake.play(Shake.steps(intensity: intensity, heavy: true),
                             reduceMotion: reduceMotion) { screenShake = $0 }
        }
    }

    // MARK: - Zone d'actions (dés + boutons côte à côte)

    private var actionArea: some View {
        VStack(spacing: 14) {
            if let pendingRoll {
                DiceRollOverlay(roll: pendingRoll,
                                durationMs: currentRollMs,
                                revealEarly: revealRollEarly)
                    .id(pendingRoll.id)
                    .transition(.opacity)
                    .contentShape(Rectangle())
                    .onTapGesture { skipDiceRoll() }
            }
            if !isRolling {
                actionBar
                    .transition(.opacity)
                    .allowsHitTesting(!isRolling)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isRolling)
        .animation(.easeInOut(duration: 0.2), value: pendingRoll?.id)
    }

    @ViewBuilder
    private var actionBar: some View {
        switch battle.phase {
        case .awaitingAction:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    BattleActionButton(label: "Attaquer",
                                       icon: "ability",
                                       tint: Theme.blood) {
                        performAttack()
                    }
                    if battle.fleeTarget != nil && !battle.fleeUsed {
                        BattleActionButton(label: "Tenter de fuir",
                                           icon: "figure.run",
                                           tint: Theme.inkFaded) {
                            showFleeConfirm = true
                        }
                    }
                }
                if onOpenInventory != nil, hasUsableConsumable {
                    BattleActionButton(label: "Utiliser un objet",
                                       icon: "drop.fill",
                                       tint: Theme.inkBlue) {
                        onOpenInventory?()
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
                    .foregroundColor(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.oldGold.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.oldGold.opacity(0.55), lineWidth: 0.7)
            )
            .shadow(color: Theme.oldGold.opacity(0.25), radius: 3, x: 0, y: 1)
            HStack(spacing: 10) {
                BattleActionButton(label: "Tenter (Chance \(player.luck))",
                                   icon: "try_luck",
                                   tint: Theme.oldGold) {
                    performLuck(offensive: offensive)
                }
                BattleActionButton(label: "Attaquer",
                                   icon: "ability",
                                   tint: Theme.blood) {
                    mutateBattle { BattleEngine.skipLuck(state: &$0) }
                    performAttack()
                }
            }
        }
    }

    // MARK: - Actions avec animation de dés

    private func performAttack() {
        guard !isRolling else { return }

        let p1 = Int.random(in: 1...6)
        let p2 = Int.random(in: 1...6)
        let e1 = Int.random(in: 1...6)
        let e2 = Int.random(in: 1...6)

        let playerAttack = p1 + p2 + player.skill + battle.playerSkillBonus
        let enemyAttack  = e1 + e2 + max(0, battle.enemy.skill - battle.enemySkillPenalty)
        let killingEnemy = playerAttack > enemyAttack && battle.enemy.stamina <= 2
        let killingPlayer = enemyAttack > playerAttack
            && player.stamina <= (2 + battle.enemy.damageBonus)
        let isClimax = killingEnemy || killingPlayer
        let effectiveRollMs = isClimax ? Int(Double(rollMs) * 1.7) : rollMs
        currentRollMs = effectiveRollMs

        AmbientAudio.shared.play(.diceRoll)
        isRolling = true
        revealRollEarly = false

        withAnimation(.easeInOut(duration: 0.15)) {
            pendingRoll = PendingDiceRoll(
                kind: .attack(
                    playerDice: (p1, p2), playerSkill: player.skill,
                    enemyDice: (e1, e2),  enemySkill: battle.enemy.skill
                )
            )
        }

        scheduleRollResolve(after: effectiveRollMs + 500) {
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
                Haptics.hit()
            } else if player.stamina < playerStaminaBefore {
                AmbientAudio.shared.play(.takeHit)
                Haptics.hit()
            } else {
                Haptics.light()
            }
            if case .ended(.victory) = battle.phase {
                triggerScreenShake(intensity: 16)
            } else if case .ended(.defeat) = battle.phase {
                triggerScreenShake(intensity: 16)
            } else if p1 + p2 == 12 && battle.enemy.stamina < enemyStaminaBefore {
                triggerScreenShake(intensity: 10)
            } else if e1 + e2 == 12 && player.stamina < playerStaminaBefore {
                triggerScreenShake(intensity: 10)
            }
            if case .ended(.victory) = battle.phase {
                Haptics.killingBlow()
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) {
                    AmbientAudio.shared.play(.enemyDie)
                }
            }
            if case .ended(.defeat) = battle.phase {
                AmbientAudio.shared.play(.death)
                Haptics.warning()
            }
        }
    }

    private func performFlee() {
        guard !isRolling else { return }
        let d1 = Int.random(in: 1...6)
        let d2 = Int.random(in: 1...6)

        AmbientAudio.shared.play(.diceRoll)
        isRolling = true
        revealRollEarly = false

        withAnimation(.easeInOut(duration: 0.15)) {
            pendingRoll = PendingDiceRoll(kind: .luck(dice: (d1, d2)))
        }

        scheduleRollResolve(after: rollMs + 500) {
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
        guard !isRolling else { return }
        let d1 = Int.random(in: 1...6)
        let d2 = Int.random(in: 1...6)

        AmbientAudio.shared.play(.diceRoll)
        isRolling = true
        revealRollEarly = false

        withAnimation(.easeInOut(duration: 0.15)) {
            pendingRoll = PendingDiceRoll(kind: .luck(dice: (d1, d2)))
        }

        scheduleRollResolve(after: rollMs + 500) {
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
                case .lucky:
                    AmbientAudio.shared.play(.lucky)
                    Haptics.light()
                case .unlucky:
                    AmbientAudio.shared.play(.unlucky)
                    Haptics.hit()
                default: break
                }
            }
            if case .ended(.victory) = battle.phase {
                Haptics.killingBlow()
                triggerScreenShake(intensity: 16)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) {
                    AmbientAudio.shared.play(.enemyDie)
                }
            } else if case .ended(.defeat) = battle.phase {
                triggerScreenShake(intensity: 16)
            }
        }
    }

    // MARK: - Tap-to-skip helpers

    private func scheduleRollResolve(after ms: Int, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        pendingResolveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: work)
    }

    private func skipDiceRoll() {
        guard isRolling, let work = pendingResolveWork else { return }
        revealRollEarly = true
        work.perform()
        work.cancel()
        pendingResolveWork = nil
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
    @State private var damageFloater: StaminaFloater? = nil
    @State private var idleBreath: CGFloat = 1.0
    @State private var hitParticleTrigger: UUID = UUID()
    @State private var showHitParticles: Bool = false
    @State private var showFullPortrait: Bool = false
    @State private var shakeTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var endRatio: Double {
        guard enemy.staminaMax > 0 else { return 0 }
        return Double(max(enemy.stamina, 0)) / Double(enemy.staminaMax)
    }

    var body: some View {
        VStack(spacing: 10) {
            fleuronDivider

            HStack(spacing: 12) {
                miniPortrait
                VStack(alignment: .leading, spacing: 2) {
                    Text(enemy.name)
                        .font(Theme.display(16))
                        .foregroundColor(Theme.parchmentLight)
                        .multilineTextAlignment(.leading)
                    if let subtitle = enemy.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular, design: .serif))
                            .italic()
                            .foregroundColor(Theme.parchmentLight.opacity(0.65))
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 22) {
                stat("Habileté", enemy.skill,
                     Color(red: 0.62, green: 0.78, blue: 1.0))
                Rectangle()
                    .fill(Theme.oldGold.opacity(0.45))
                    .frame(width: 0.5, height: 22)
                stat("Endurance", max(enemy.stamina, 0),
                     Color(red: 1.0, green: 0.55, blue: 0.48))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.ink.opacity(0.55))
                    Capsule()
                        .fill(Theme.blood)
                        .frame(width: geo.size.width * endRatio)
                        .animation(.easeOut(duration: 0.5), value: endRatio)
                }
            }
            .frame(height: 6)

            if let note = enemy.abilityNote {
                let abilityRed = Color(red: 1.0, green: 0.62, blue: 0.55)
                HStack(spacing: 5) {
                    Theme.icon("claw", size: 9, color: abilityRed)
                    Text(note)
                        .font(Theme.display(10))
                }
                .foregroundColor(abilityRed)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.ink.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(abilityRed.opacity(0.75), lineWidth: 0.6)
                )
            }

            fleuronDivider
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.46, green: 0.34, blue: 0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.blood.opacity(flash ? 0.30 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.oldGold.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Theme.ink.opacity(0.45), radius: 10, x: 0, y: 4)
        .offset(x: shakeOffset)
        .overlay(alignment: .topTrailing) {
            if let floater = damageFloater {
                FloatingDamage(value: floater.value)
                    .id(floater.id)
                    .padding(.trailing, 20)
                    .padding(.top, 10)
            }
        }
        .overlay(alignment: .center) {
            if showHitParticles {
                HitParticles(tint: Theme.blood)
                    .id(hitParticleTrigger)
            }
        }
        .onAppear {
            lastStamina = enemy.stamina
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                idleBreath = 1.03
            }
        }
        .onDisappear {
            shakeTask?.cancel()
            shakeTask = nil
        }
        .onChange(of: enemy.stamina) { oldValue, newValue in
            let delta = newValue - oldValue
            if delta < 0 {
                triggerHit()
                if !reduceMotion {
                    hitParticleTrigger = UUID()
                    showHitParticles = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showHitParticles = false
                    }
                }
            }
            AmbientAudio.shared.setBattleIntensity(
                enemyHpRatio: Double(max(newValue, 0)) / Double(max(1, enemy.staminaMax))
            )
            if delta != 0 {
                damageFloater = StaminaFloater(value: delta)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if damageFloater?.value == delta {
                        damageFloater = nil
                    }
                }
            }
            lastStamina = newValue
        }
        .fullScreenCover(isPresented: $showFullPortrait) {
            EnemyPortraitFullScreen(enemy: enemy)
        }
    }

    @ViewBuilder
    private var miniPortrait: some View {
        if let img = Theme.enemyPortrait(enemy.id) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipped()
                .saturation(portraitSaturation)
                .colorMultiply(portraitTint)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Theme.inkFaded.opacity(0.5), lineWidth: 0.6)
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Theme.parchmentLight)
                        .padding(2)
                        .background(
                            Circle().fill(Theme.ink.opacity(0.7))
                        )
                        .offset(x: 3, y: -3)
                }
                .scaleEffect(idleBreath)
                .minimumTapTarget()
                .onTapGesture {
                    showFullPortrait = true
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Voir le portrait de \(enemy.name) en grand")
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.inkFaded.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "questionmark")
                        .foregroundColor(Theme.inkFaded)
                )
                .scaleEffect(idleBreath)
        }
    }

    private var portraitSaturation: Double {
        let ratio = endRatio
        if ratio >= 0.7 { return 1.0 }
        if ratio >= 0.35 { return 0.6 }
        return 0.25
    }

    private var portraitTint: Color {
        let ratio = endRatio
        if ratio >= 0.7 { return Color.white }
        if ratio >= 0.35 { return Theme.blood.opacity(0.85) }
        return Theme.inkFaded
    }

    private func triggerHit() {
        let killing = enemy.stamina <= 0
        let flashDuration = killing ? 0.30 : 0.12
        let flashHold = killing ? 0.40 : 0.18
        withAnimation(.easeOut(duration: flashDuration)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + flashHold) {
            withAnimation(.easeIn(duration: 0.35)) { flash = false }
        }
        shakeTask?.cancel()
        shakeTask = Task { @MainActor in
            await Shake.play(Shake.steps(intensity: killing ? 14 : 8, heavy: killing),
                             reduceMotion: reduceMotion) { shakeOffset = $0 }
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.display(9))
                .tracking(1.2)
                .foregroundColor(Theme.parchmentLight.opacity(0.85))
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(color)
        }
    }

    private var fleuronDivider: some View {
        HStack(spacing: 8) {
            fleuron
            Rectangle()
                .fill(Theme.oldGold.opacity(0.55))
                .frame(height: 0.6)
            fleuron
            Rectangle()
                .fill(Theme.oldGold.opacity(0.55))
                .frame(height: 0.6)
            fleuron
        }
    }

    private var fleuron: some View {
        Image(systemName: "diamond.fill")
            .font(.system(size: 5))
            .foregroundColor(Theme.oldGold)
    }
}

// MARK: - Vue plein écran du portrait

enum EnemyPortraitMode {
    case tapToClose
    case preCombat(onContinue: () -> Void)
}

struct EnemyPortraitFullScreen: View {
    let enemy: Enemy
    var mode: EnemyPortraitMode = .tapToClose

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.18, green: 0.13, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer(minLength: 0)

                if let img = Theme.enemyPortrait(enemy.id) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(.horizontal, 18)
                        .overlay(
                            Rectangle()
                                .stroke(Theme.oldGold.opacity(0.55), lineWidth: 1)
                                .padding(.horizontal, 18)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.inkFaded.opacity(0.2))
                        .frame(maxWidth: 280, maxHeight: 280)
                        .overlay(
                            Image(systemName: "questionmark")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.inkFaded)
                        )
                }

                Text(enemy.name)
                    .font(Theme.display(22))
                    .foregroundColor(Theme.parchmentLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                HStack(spacing: 26) {
                    stat("Habileté", enemy.skill,
                         Color(red: 0.62, green: 0.78, blue: 1.0))
                    Rectangle()
                        .fill(Theme.oldGold.opacity(0.45))
                        .frame(width: 0.6, height: 22)
                    stat("Endurance", enemy.staminaMax,
                         Color(red: 1.0, green: 0.55, blue: 0.48))
                }

                if let note = enemy.abilityNote {
                    let abilityRed = Color(red: 1.0, green: 0.62, blue: 0.55)
                    HStack(spacing: 5) {
                        Theme.icon("claw", size: 11, color: abilityRed)
                        Text(note)
                            .font(Theme.display(11))
                    }
                    .foregroundColor(abilityRed)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.ink.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(abilityRed.opacity(0.75), lineWidth: 0.6)
                    )
                }

                Spacer(minLength: 0)

                switch mode {
                case .tapToClose:
                    Text("Touche pour fermer")
                        .font(Theme.display(11))
                        .tracking(1.5)
                        .foregroundColor(Theme.parchmentDark.opacity(0.85))
                        .padding(.bottom, 24)
                case .preCombat(let onContinue):
                    Button(action: onContinue) {
                        HStack(spacing: 10) {
                            Text("Entrer en combat")
                                .font(Theme.display(14))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(IllustrationContinueStyle())
                    .padding(.bottom, 32)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if case .tapToClose = mode {
                dismiss()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Fermer le portrait")
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(Theme.display(9))
                .tracking(1.5)
                .foregroundColor(Theme.parchmentLight.opacity(0.85))
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(color)
        }
    }
}

// MARK: - Journal de combat

struct BattleLog: View {
    let entries: [BattleLogEntry]

    private let maxHeight: CGFloat = 130

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Theme.icon(symbol(for: entry),
                                       size: entry.kind == .end ? 16 : 13,
                                       color: color(for: entry.kind))
                                .frame(width: 22, alignment: .center)
                            Text(entry.text)
                                .font(entry.kind == .end
                                      ? Theme.body(15).bold()
                                      : Theme.body(14))
                                .foregroundColor(Theme.ink)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(3)
                            Spacer(minLength: 0)
                        }
                        .id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("log-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: maxHeight)
            .onChange(of: entries.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("log-bottom", anchor: .bottom)
            }
        }
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

    private func symbol(for entry: BattleLogEntry) -> String {
        switch entry.kind {
        case .info:     return "info.circle.fill"
        case .hitDealt: return "attack"
        case .hitTaken: return "heal_down"
        case .miss:     return "tie"
        case .lucky:    return "try_luck"
        case .unlucky:  return "trap"
        case .end:
            let t = entry.text.lowercased()
            if t.contains("prends la fuite") || t.contains("tu fuis") {
                return "flee"
            }
            return "dead"
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
                    Theme.icon(icon, size: 13, color: Theme.parchmentLight)
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
    }
}

// MARK: - (BattleIntroCard retiré)
//
// L'ancienne carte plein écran « title card » qui s'affichait pendant
// quelques secondes au début du combat est désormais supprimée. Son style
// (fond ink + fleurons + bordure or) a été appliqué directement à la
// EnemyCard, qui joue donc en permanence le rôle de présentation
// dramatique de l'ennemi pendant le combat.
