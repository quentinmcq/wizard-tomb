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
    /// Closure pour ouvrir la feuille d'inventaire au milieu d'un combat
    /// (boire une potion entre deux rounds). Nil = pas de bouton "Objet".
    var onOpenInventory: (() -> Void)? = nil

    @State private var pendingRoll: PendingDiceRoll? = nil
    /// True pendant que l'animation des dés joue. Cache la barre d'actions
    /// pour éviter qu'un tap interrompe le roll en cours. Une fois à false,
    /// les boutons reviennent SANS effacer le pendingRoll (les valeurs des
    /// dés restent à l'écran jusqu'à la prochaine action).
    @State private var isRolling: Bool = false
    /// Durée effective du roll courant. Normalement égale à `rollMs`, mais
    /// étendue (#12 slow-mo) sur un coup potentiellement mortel.
    @State private var currentRollMs: Int = 1600
    /// #6 — Décalage horizontal du contenu pour le shake d'écran sur crit
    /// ou coup de grâce. Animé brièvement puis remis à 0.
    @State private var screenShake: CGFloat = 0
    /// #8 — Affiche le dialogue de confirmation avant la tentative de
    /// fuite. Une seule chance, on demande confirmation.
    @State private var showFleeConfirm: Bool = false

    /// Durée totale de l'animation des dés (chute + rotation + bounce).
    private let rollMs = 1600

    /// True si le joueur a au moins un consommable utile dans son sac
    /// (potion, herbes, viande, items combat) qui produirait un effet réel
    /// ici. Évite d'afficher un bouton "Objet" qui n'aurait rien à proposer.
    private var hasUsableConsumable: Bool {
        player.items.contains { id in
            guard let effect = ItemCatalog.all[id]?.consumable else { return false }
            switch effect {
            case .heal:        return player.stamina < player.staminaMax
            case .restoreLuck: return player.luck < player.luckMax
            case .boostSkillNextAttack, .weakenEnemyNextAttack:
                return true  // toujours utile en combat (on est ici, donc OK)
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
        .offset(x: screenShake)  // #6
        // L'ancienne BattleIntroCard plein écran a été retirée : la
        // EnemyCard hérite maintenant de son style (fond ink + fleurons +
        // bordure or), elle joue donc le rôle de title card en permanence
        // au lieu d'apparaître et disparaître au début du combat.
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

    /// Déclenche un shake horizontal sur l'ensemble du contenu de combat.
    /// `intensity` = amplitude max (small = crit ennemi, large = killing
    /// blow). Joue ~0.35s.
    private func triggerScreenShake(intensity: CGFloat) {
        let amplitudes: [(CGFloat, Double)] = [
            (-intensity, 0.05),
            (intensity, 0.05),
            (-intensity * 0.7, 0.05),
            (intensity * 0.7, 0.05),
            (-intensity * 0.4, 0.05),
            (intensity * 0.4, 0.05),
            (0, 0.05)
        ]
        var delay: Double = 0
        for (amp, dur) in amplitudes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: dur)) { screenShake = amp }
            }
            delay += dur
        }
    }

    // MARK: - Zone d'actions (dés + boutons côte à côte)

    private var actionArea: some View {
        VStack(spacing: 14) {
            if let pendingRoll {
                DiceRollOverlay(roll: pendingRoll, durationMs: currentRollMs)
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
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    BattleActionButton(label: "Attaquer",
                                       icon: "ability",
                                       tint: Theme.blood) {
                        performAttack()
                    }
                    // Bouton "Tenter de fuir" disponible seulement si le knot
                    // l'autorise ET si on n'a pas déjà tenté : une seule chance
                    // par combat, échec ou réussite. #8 — On confirme d'abord :
                    // l'irréversibilité justifie un tap supplémentaire.
                    if battle.fleeTarget != nil && !battle.fleeUsed {
                        BattleActionButton(label: "Tenter de fuir",
                                           icon: "figure.run",
                                           tint: Theme.inkFaded) {
                            showFleeConfirm = true
                        }
                    }
                }
                // Bouton "Objet" : ouvre l'inventaire mid-combat pour boire
                // une potion / utiliser un consommable. N'apparaît que si on
                // a au moins un consommable dans le sac.
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
        // #8 — Cartouche doré autour de la prompt pour la rendre plus
        // appelante visuellement. Petit glow + bordure or qui pulse
        // subtilement pour attirer l'œil.
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
        let p1 = Int.random(in: 1...6)
        let p2 = Int.random(in: 1...6)
        let e1 = Int.random(in: 1...6)
        let e2 = Int.random(in: 1...6)

        // #12 — Détecte si ce round est potentiellement mortel (ennemi
        // qui passerait à 0 ou joueur qui passerait à 0) et étire la
        // durée du roll de ~70 % pour un effet « slow-mo cinéma ».
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

        withAnimation(.easeInOut(duration: 0.15)) {
            pendingRoll = PendingDiceRoll(
                kind: .attack(
                    playerDice: (p1, p2), playerSkill: player.skill,
                    enemyDice: (e1, e2),  enemySkill: battle.enemy.skill
                )
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(effectiveRollMs + 500)) {
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
                Haptics.light()  // miss
            }
            // #6 — Shake d'écran sur crit (2d6 = 12) ou coup de grâce.
            // Un crit ennemi qui touche : shake moyen.
            // Un crit joueur qui touche : shake moyen.
            // Killing blow (victoire ou défaite) : shake fort.
            if case .ended(.victory) = battle.phase {
                triggerScreenShake(intensity: 16)
            } else if case .ended(.defeat) = battle.phase {
                triggerScreenShake(intensity: 16)
            } else if p1 + p2 == 12 && battle.enemy.stamina < enemyStaminaBefore {
                triggerScreenShake(intensity: 10)
            } else if e1 + e2 == 12 && player.stamina < playerStaminaBefore {
                triggerScreenShake(intensity: 10)
            }
            // Râle final juste après l'impact qui termine l'ennemi, avant le
            // bouton "Continuer". Court délai pour ne pas se superposer au
            // hitDealt qui vient de jouer.
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
                case .lucky:
                    AmbientAudio.shared.play(.lucky)
                    Haptics.light()
                case .unlucky:
                    AmbientAudio.shared.play(.unlucky)
                    Haptics.hit()
                default: break
                }
            }
            // Mort de l'ennemi via test de Chance offensif (rare mais
            // possible : un coup chanceux pousse la jauge à 0).
            if case .ended(.victory) = battle.phase {
                Haptics.killingBlow()
                triggerScreenShake(intensity: 16)  // #6
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) {
                    AmbientAudio.shared.play(.enemyDie)
                }
            } else if case .ended(.defeat) = battle.phase {
                triggerScreenShake(intensity: 16)  // #6
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
    @State private var damageFloater: StaminaFloater? = nil
    /// Idle subtil sur le portrait : scale qui oscille doucement pour
    /// donner l'illusion d'une respiration. Mise à jour via .onAppear
    /// avec une animation repeatForever.
    @State private var idleBreath: CGFloat = 1.0
    /// Gerbe d'éclats au moment du hit. Trigger redéclenché à chaque hit
    /// pour rejouer l'animation.
    @State private var hitParticleTrigger: UUID = UUID()
    @State private var showHitParticles: Bool = false
    /// True quand le joueur a tapé le mini-portrait pour le voir en grand
    /// (overlay plein écran).
    @State private var showFullPortrait: Bool = false

    private var endRatio: Double {
        guard enemy.staminaMax > 0 else { return 0 }
        return Double(max(enemy.stamina, 0)) / Double(enemy.staminaMax)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Fleuron décoratif en haut, hérité du style de la carte
            // d'intro de combat (qui disparaît au profit de cette carte).
            fleuronDivider

            // Mini-portrait à gauche du nom. Teinté selon la vie restante
            // (du normal au fantomatique) et anime doucement comme s'il
            // respirait.
            HStack(spacing: 12) {
                miniPortrait
                Text(enemy.name)
                    .font(Theme.display(16))
                    .foregroundColor(Theme.parchmentLight)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }

            HStack(spacing: 22) {
                stat("Habileté", enemy.skill, Theme.inkBlue.opacity(0.95))
                Rectangle()
                    .fill(Theme.oldGold.opacity(0.45))
                    .frame(width: 0.5, height: 22)
                stat("Endurance", max(enemy.stamina, 0), Theme.blood.opacity(0.95))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.ink.opacity(0.55))  // track plus contrasté sur le fond éclairci
                    Capsule()
                        .fill(Theme.blood)
                        .frame(width: geo.size.width * endRatio)
                        .animation(.easeOut(duration: 0.5), value: endRatio)
                }
            }
            .frame(height: 6)

            if let note = enemy.abilityNote {
                HStack(spacing: 5) {
                    Theme.icon("claw", size: 9, color: Theme.blood)
                    Text(note)
                        .font(Theme.display(10))
                }
                .foregroundColor(Theme.blood)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.blood.opacity(0.20))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Theme.blood.opacity(0.55), lineWidth: 0.5)
                )
            }

            // Fleuron du bas — symétrie avec le haut, pour le côté
            // "title card" qu'on cherchait avec l'intro.
            fleuronDivider
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            // Fond brun-encre chaud (basé sur inkFaded plutôt qu'ink pur)
            // : on garde l'effet « title card » mais le contenu (texte,
            // stats) reste lisible — l'ancien `Theme.ink.opacity(0.92)`
            // était presque noir et écrasait tout ce qu'il portait.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.inkFaded.opacity(0.92))
        )
        .overlay(
            // Flash rouge bref quand l'ennemi encaisse, par-dessus le fond.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.blood.opacity(flash ? 0.30 : 0))
        )
        .overlay(
            // Bordure or, signature du style "title card".
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
            // Démarre la respiration : scale qui oscille entre 0.97 et 1.03
            // en boucle infinie, vitesse modérée pour ne pas distraire.
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                idleBreath = 1.03
            }
        }
        .onChange(of: enemy.stamina) { oldValue, newValue in
            let delta = newValue - oldValue
            if delta < 0 {
                triggerHit()
                hitParticleTrigger = UUID()
                showHitParticles = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showHitParticles = false
                }
            }
            // #14 — Musique de combat qui s'intensifie quand l'ennemi
            // approche de la mort. Le wrapper audio fait la rampe douce.
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
        // Vue plein écran du portrait : déclenchée par un tap sur le
        // mini-portrait. Le joueur peut détailler le monstre avant ou
        // pendant le combat.
        .fullScreenCover(isPresented: $showFullPortrait) {
            EnemyPortraitFullScreen(enemy: enemy)
        }
    }

    /// Mini-portrait de l'ennemi (40×40) avec teinture progressive selon
    /// la vie restante : plein → léger gris pâle, mi-vie → décoloré, près
    /// de la mort → fantomatique. Cherche `<id>.jpg` puis fallback
    /// `<id sans _phaseN>.jpg` pour réutiliser le portrait des combats
    /// multi-phases.
    @ViewBuilder
    private var miniPortrait: some View {
        if let img = Self.loadEnemyPortrait(enemyId: enemy.id) {
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
                // Petit signal visuel : on indique que le portrait est
                // tappable pour le voir en grand. Loupe en haut-droite.
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
                .contentShape(Rectangle())
                .onTapGesture {
                    showFullPortrait = true
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Voir le portrait de \(enemy.name) en grand")
        } else {
            // Pas d'image trouvée : carré gris avec un point d'exclamation,
            // utile en dev quand on rajoute un ennemi sans encore avoir
            // son portrait dans le bundle.
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

    /// Saturation du portrait. Plein de vie = 1.0 ; à mi-stamina ~0.6 ;
    /// près de la mort ~0.2 (presque noir et blanc).
    private var portraitSaturation: Double {
        let ratio = endRatio
        if ratio >= 0.7 { return 1.0 }
        if ratio >= 0.35 { return 0.6 }
        return 0.25
    }

    /// Teinte appliquée par color-multiply. Plein = parchemin clair ;
    /// blessé = légèrement rouge ; mourant = encre froide (fantomatique).
    private var portraitTint: Color {
        let ratio = endRatio
        if ratio >= 0.7 { return Color.white }
        if ratio >= 0.35 { return Theme.blood.opacity(0.85) }
        return Theme.inkFaded
    }

    static func loadEnemyPortrait(enemyId: String) -> UIImage? {
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

    private func triggerHit() {
        // #7 — Si l'ennemi tombe à 0, on amplifie : flash plus long, shake
        // plus amplifié. Le moment du coup de grâce mérite sa pause.
        let killing = enemy.stamina <= 0
        let flashDuration = killing ? 0.30 : 0.12
        let flashHold = killing ? 0.40 : 0.18
        withAnimation(.easeOut(duration: flashDuration)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + flashHold) {
            withAnimation(.easeIn(duration: 0.35)) { flash = false }
        }
        // Shake horizontal (sprint d'aller-retours)
        let amplitudes: [(CGFloat, Double)] = killing
            ? [(-14, 0.06), (14, 0.06), (-10, 0.06), (10, 0.06), (-6, 0.06), (6, 0.06), (0, 0.08)]
            : [(-8, 0.05), (8, 0.05), (-5, 0.05), (5, 0.05), (0, 0.05)]
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
            Text(label.uppercased())
                .font(Theme.display(9))
                .tracking(1.2)
                .foregroundColor(Theme.parchmentLight.opacity(0.85))
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(color)
        }
    }

    /// Liseré décoratif fleurons-or-fleurons, repris du style « title card »
    /// de l'ancienne BattleIntroCard pour donner du caractère à la carte
    /// pendant le combat (au lieu d'un cadre cuir parchemin).
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

/// Affichée quand le joueur tape le mini-portrait de l'ennemi. Le portrait
/// est montré à pleine largeur avec le nom et les stats sous l'image, sur
/// fond sombre. Tap sur l'image ou sur le bouton X pour fermer.
struct EnemyPortraitFullScreen: View {
    let enemy: Enemy

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Fond sombre opaque pour isoler le portrait. Le ignoresSafeArea
            // évite la barre blanche en haut/bas.
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer(minLength: 0)

                if let img = EnemyCard.loadEnemyPortrait(enemyId: enemy.id) {
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
                    stat("Habileté", enemy.skill, Theme.inkBlue.opacity(0.95))
                    Rectangle()
                        .fill(Theme.oldGold.opacity(0.45))
                        .frame(width: 0.6, height: 22)
                    stat("Endurance", enemy.staminaMax, Theme.blood.opacity(0.95))
                }

                if let note = enemy.abilityNote {
                    HStack(spacing: 5) {
                        Theme.icon("claw", size: 11, color: Theme.blood)
                        Text(note)
                            .font(Theme.display(11))
                    }
                    .foregroundColor(Theme.blood)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.blood.opacity(0.20))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Theme.blood.opacity(0.55), lineWidth: 0.5)
                    )
                }

                Spacer(minLength: 0)

                // Hint discret en bas — la zone entière est tappable mais
                // on indique quand même la convention.
                Text("Touche pour fermer")
                    .font(Theme.display(11))
                    .tracking(1.5)
                    .foregroundColor(Theme.parchmentDark.opacity(0.7))
                    .padding(.bottom, 24)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
        // Bouton X en haut-droite pour les utilisateurs qui préfèrent
        // un point d'action explicite.
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.parchmentLight.opacity(0.85), Color.black.opacity(0.6))
            }
            .padding(.top, 14)
            .padding(.trailing, 14)
            .accessibilityLabel("Fermer le portrait")
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(Theme.display(9))
                .tracking(1.5)
                .foregroundColor(Theme.parchmentDark)
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(color)
        }
    }
}

// MARK: - Journal de combat

struct BattleLog: View {
    let entries: [BattleLogEntry]

    /// Hauteur max du log avant scroll. Calibrée pour afficher ~4 lignes
    /// confortablement sur iPhone, sans manger l'espace des boutons.
    private let maxHeight: CGFloat = 130

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            // Theme.icon route automatiquement vers les
                            // assets pixel-art (attack, heal_down, tie…)
                            // ou SF Symbol sinon.
                            Theme.icon(symbol(for: entry.kind),
                                       size: 13,
                                       color: color(for: entry.kind))
                                .frame(width: 22, alignment: .center)
                            Text(entry.text)
                                .font(Theme.body(14))
                                .foregroundColor(Theme.ink)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(3)
                            Spacer(minLength: 0)
                        }
                        .id(entry.id)
                    }
                    // Sentinel pour auto-scroll : on cible cet anchor, qui
                    // est toujours en bas du contenu.
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

    private func symbol(for kind: BattleLogEntry.Kind) -> String {
        switch kind {
        case .info:     return "info.circle.fill"
        case .hitDealt: return "attack"      // pixel-art : coup porté
        case .hitTaken: return "heal_down"   // pixel-art : on encaisse
        case .miss:     return "tie"         // pixel-art : égalité / parade
        case .lucky:    return "sparkles"
        case .unlucky:  return "trap"        // pixel-art : tour défavorable de la Chance
        case .end:      return "dead"        // pixel-art : monstre abattu (ou défaite côté joueur)
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

// MARK: - (BattleIntroCard retiré)
//
// L'ancienne carte plein écran « title card » qui s'affichait pendant
// quelques secondes au début du combat est désormais supprimée. Son style
// (fond ink + fleurons + bordure or) a été appliqué directement à la
// EnemyCard, qui joue donc en permanence le rôle de présentation
// dramatique de l'ennemi pendant le combat.
