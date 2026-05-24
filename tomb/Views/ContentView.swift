//
//  ContentView.swift
//  UI principale du jeu, ambiance "vieux bouquin".
//  La logique narrative est dans GameSession (qui pilote InkStory).
//

import SwiftUI

struct ContentView: View {
    @StateObject private var session = GameSession()
    @StateObject private var audio = AmbientAudio.shared
    @State private var showingInventory = false
    @State private var showingMenuConfirm = false
    /// True once the typewriter for the current passage has finished. Gates
    /// the visibility of the choices / ending button so they don't jump
    /// while the text grows.
    @State private var passageRevealed = false
    /// Verrou anti-double-tap : passe à true dès qu'un choix est consommé,
    /// retombe à false quand le passage suivant est entièrement révélé.
    /// Évite que plusieurs `pageTurn` se jouent si le joueur martèle un
    /// bouton (le bouton met ~350 ms à disparaître visuellement).
    @State private var isChoosing = false

    // MARK: - Page-turn orchestration

    /// Text actually rendered by `PassageText`. May briefly lag behind
    /// `session.currentText` during the 3D flip so that the swap happens
    /// while the page is edge-on (invisible to the camera).
    @State private var visibleText: String = ""
    /// Rotation angle (degrees) around the Y axis, driving the page-turn.
    @State private var pageRotation: Double = 0
    /// Half-duration of the flip (out, then back in).
    private let flipHalfMs = 280
    @State private var flipTask: Task<Void, Never>? = nil

    /// Filtre les marginalia : tant qu'un jet de Chance narratif est affiché
    /// au centre de l'écran (les dés roulent), on masque les messages de
    /// type `.lucky` / `.unlucky` pour ne pas spoiler le résultat dans la
    /// marge avant que les dés ne se posent.
    private var visibleMargins: [EventMessage] {
        guard session.pendingNarrativeLuck != nil else { return session.lastMessages }
        return session.lastMessages.filter { $0.kind != .lucky && $0.kind != .unlucky }
    }

    /// Nombre d'items consommables actuellement dans le sac. Calculé ici
    /// pour alimenter le badge du bouton inventaire dans le HUD.
    private var consumableCount: Int {
        session.player.items.reduce(0) { acc, id in
            acc + (ItemCatalog.all[id]?.consumable != nil ? 1 : 0)
        }
    }

    var body: some View {
        ZStack {
            Theme.pageBackground

            // #13 — Voile sombre subtil pendant un combat. Donne l'impression
            // que la page s'assombrit autour de l'action, pour signaler
            // qu'on est ailleurs que dans l'exploration. Pas appliqué quand
            // l'illustration plein-page (avant combat) est encore visible.
            if session.pendingBattle != nil && session.pendingIllustration == nil {
                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if session.hasStarted {
                gameView
                    .transition(.opacity)
            } else if session.isCreatingCharacter {
                CharacterCreationView(session: session, audio: audio)
                    .transition(.opacity)
            } else {
                MenuView(session: session, audio: audio)
                    .transition(.opacity)
            }

            // Central effect burst overlay (item gain, permanent bonus...)
            if let burst = session.effectBurst {
                EffectBurstView(burst: burst)
                    .id(burst.id)
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            // Narrative luck roll overlay (traps, cursed book, amulet grab)
            if let luckRoll = session.pendingNarrativeLuck {
                NarrativeLuckOverlay(roll: luckRoll)
                    .id(luckRoll.id)
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

            // Planche illustrée pleine page (façon Défis Fantastiques).
            // Cache le passage et les choix tant qu'elle est visible.
            //
            // Deux cas :
            //   1. L'illustration correspond à un ennemi connu → on
            //      affiche une carte stats-riche (EnemyPortraitFullScreen
            //      en mode preCombat) : nom, SK/ST, aptitude, dans le
            //      cadre or sur fond brun cuir. Le joueur sait à quoi il
            //      a affaire avant de cliquer « Entrer en combat ».
            //   2. Sinon (scène narrative type Tellor, porte finale) →
            //      illustration simple + bouton « Continuer ».
            if let illustration = session.pendingIllustration {
                Group {
                    if let enemy = EnemyCatalog.all[illustration] {
                        EnemyPortraitFullScreen(
                            enemy: enemy,
                            mode: .preCombat(onContinue: {
                                session.dismissIllustration()
                            })
                        )
                    } else {
                        FullPageIllustration(name: illustration) {
                            session.dismissIllustration()
                        }
                    }
                }
                .id("illustration-\(illustration)")
                .transition(.opacity)
                .zIndex(10)
            }

            // #9 — Vignette rouge sur les bords quand stamina critique
            // (< 25%). Pulse subtil pour signaler la tension sans masquer
            // l'écran. N'apparaît que pendant un combat actif (sinon
            // l'effet est confusant en exploration / sur les écrans
            // narratifs).
            if session.pendingBattle != nil && session.player.staminaMax > 0 {
                let ratio = Double(max(session.player.stamina, 0))
                    / Double(session.player.staminaMax)
                if ratio < 0.25 {
                    CriticalHealthVignette()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                        .zIndex(15)
                        .transition(.opacity)
                }
            }

            // Transition cinématique de chapitre : fondu noir + titre
            // plein écran (Chapitre III — Le marais) pendant ~2.5 s
            // quand on franchit un # chapter:. Zindex max pour passer
            // par-dessus tout (combat, illustration, vignette critique).
            if let newChapter = session.pendingChapterTransition {
                ChapterTransitionOverlay(chapter: newChapter) {
                    session.pendingChapterTransition = nil
                }
                .ignoresSafeArea()
                .zIndex(50)
                .transition(.opacity)
            }

            // Mort cinématique : voile rouge → noir + épitaphe, en
            // attente de l'écran de fin. Z-index encore plus haut que la
            // transition de chapitre — la mort prime sur tout.
            if session.deathCinematicActive {
                DeathCinematicOverlay {
                    session.deathCinematicActive = false
                }
                .ignoresSafeArea()
                .zIndex(60)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.hasStarted)
        .animation(.easeInOut(duration: 0.35), value: session.isCreatingCharacter)
        .animation(.easeIn(duration: 0.35), value: passageRevealed)
        .sheet(isPresented: $showingInventory) {
            InventoryView(session: session)
        }
        .alert(
            "Quitter l'aventure ?",
            isPresented: $showingMenuConfirm
        ) {
            // `.alert` (vs `.confirmationDialog`) rend les deux boutons
            // côte à côte au lieu de releguer le bouton .cancel dans une
            // section séparée en bas de feuille. Ainsi « Non » est aussi
            // visible et tappable que « Oui ».
            Button("Non", role: .cancel) {}
            Button("Oui", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    session.backToMenu()
                }
            }
        } message: {
            Text("Ta progression sera conservée. Tu pourras la reprendre depuis le menu principal.")
        }
    }

    // MARK: - Vue jeu

    private var gameView: some View {
        VStack(spacing: 0) {
            if session.pendingBattle != nil {
                // Mode combat : on libère un maximum de hauteur en montrant
                // seulement les stats vitales et un bouton de sortie. Pas
                // de bandeau chapitre (il ne change pas pendant un combat
                // et n'apporte aucune info utile à l'action).
                //
                // Le state change qui présente l'alert est différé d'un
                // tick runloop (`DispatchQueue.main.async`) : ça laisse
                // le tap se terminer proprement avant que SwiftUI ne
                // démarre la présentation. Sans ça, en combat (vue
                // chargée d'animations + overlays), la présentation
                // bloquait le main thread ~2 s, faisait grésiller l'audio
                // et déclenchait un warning « System gesture gate timed out ».
                // Mode combat : chapter masqué, gold/inventaire masqués,
                // hit reactions actives, jauge avec preview de dégât
                // anticipé. Le contexte est libéré au max pour l'action.
                GameHUD(
                    player: session.player,
                    chapter: nil,
                    anticipatedDamage: (session.pendingBattle?.enemy.damageBonus).map { 2 + $0 } ?? 0,
                    showsResourcesAndInventory: false,
                    isInCombat: true,
                    consumableCount: 0,
                    inventoryPulseTrigger: 0,
                    potionsUsed: session.potionsUsedThisRun,
                    onOpenInventory: { },
                    onReturnToMenu: {
                        DispatchQueue.main.async {
                            showingMenuConfirm = true
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            } else {
                // Mode exploration : chip chapter, gold + inventaire,
                // pas de réactions de hit (l'aventure est calme par défaut),
                // pas de damage preview.
                GameHUD(
                    player: session.player,
                    chapter: session.currentChapter,
                    anticipatedDamage: 0,
                    showsResourcesAndInventory: true,
                    isInCombat: false,
                    consumableCount: consumableCount,
                    inventoryPulseTrigger: session.inventoryPulse,
                    potionsUsed: session.potionsUsedThisRun,
                    onOpenInventory: {
                        DispatchQueue.main.async {
                            showingInventory = true
                        }
                    },
                    onReturnToMenu: {
                        DispatchQueue.main.async {
                            showingMenuConfirm = true
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Bandeau de chapitre (image + titre) retiré pour l'instant.
                // À remettre via `ChapterBanner(chapter: session.currentChapter)`
                // si on rétablit l'indicateur de progression narrative.
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {

                        if session.pendingBattle != nil {
                            BattleView(battle: session.battleBinding,
                                       player: session.playerBinding,
                                       onEnd: session.resolveBattle,
                                       onOpenInventory: { showingInventory = true })
                                .id("text")
                                .transition(.opacity)
                        } else {
                            if !visibleMargins.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(visibleMargins) { msg in
                                        MarginNote(message: msg)
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .animation(.easeInOut(duration: 0.35),
                                           value: visibleMargins.count)
                            }

                            ZStack {
                                PassageText(text: visibleText,
                                            isComplete: $passageRevealed)
                                    .id("passage-\(visibleText.hashValue)")
                            }
                            // Ancrage sur le bord intérieur (gauche) : la
                            // page pivote comme une vraie feuille reliée
                            // à la tranche, pas comme une carte à jouer
                            // qui flippe sur son axe central. La
                            // perspective plus marquée (0.6 au lieu de
                            // 0.4) accentue la profondeur de la rotation.
                            .rotation3DEffect(.degrees(pageRotation),
                                              axis: (x: 0, y: 1, z: 0),
                                              anchor: .leading,
                                              perspective: 0.6)
                            // Ombre douce sur le bord libre (à droite) qui
                            // s'intensifie au pic de la rotation : simule
                            // la courbure de la page qui se soulève.
                            .overlay(alignment: .trailing) {
                                let intensity = min(1.0, abs(pageRotation) / 90.0)
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Theme.ink.opacity(0.25 * intensity)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 80)
                                .allowsHitTesting(false)
                            }
                            // Page edge-on → fully invisible, avoids any
                            // ghosting of old text against new.
                            .opacity(abs(pageRotation) > 85 ? 0 : 1)
                            .id("text")

                            if passageRevealed && session.pendingNarrativeLuck == nil {
                                if session.isEnded {
                                    endingButtons
                                        .transition(.opacity)
                                } else if let prompt = session.pendingLuckPrompt {
                                    LuckPromptButton(label: prompt.buttonLabel) {
                                        session.triggerLuckRoll()
                                    }
                                    .transition(.opacity)
                                } else {
                                    ChoicesList(
                                        choices: session.currentChoices,
                                        playerGold: session.player.gold,
                                        onChoose: { choice in
                                            // Debounce : si un choix a déjà
                                            // été pris, on ignore les taps
                                            // suivants jusqu'à ce que le
                                            // nouveau passage soit révélé.
                                            guard !isChoosing else { return }
                                            isChoosing = true
                                            // Hide choices immediately so a
                                            // late tap doesn't land on them
                                            // while the page is flipping.
                                            passageRevealed = false
                                            AmbientAudio.shared.play(.pageTurn)
                                            session.choose(choice)
                                            // Scroll back up so the new
                                            // passage starts at the top.
                                            DispatchQueue.main.asyncAfter(
                                                deadline: .now() + .milliseconds(flipHalfMs)
                                            ) {
                                                withAnimation(.easeOut(duration: 0.3)) {
                                                    proxy.scrollTo("text", anchor: .top)
                                                }
                                            }
                                        }
                                    )
                                    .transition(.opacity)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
            }
        }
        .onAppear { syncVisibleText() }
        .onChange(of: session.currentText) { _, newText in
            flipTo(newText)
        }
        .onChange(of: passageRevealed) { _, revealed in
            // Réautorise un nouveau choix dès que le passage suivant est
            // entièrement rendu (typewriter terminé). Tant que `revealed`
            // reste à false, le verrou tient et les taps répétés sont
            // ignorés.
            if revealed { isChoosing = false }
        }
    }

    // MARK: - Page-turn

    private func syncVisibleText() {
        // `.onChange(of: session.currentText)` est attaché à gameView : il ne
        // tire pas tant que la `gameView` n'est pas dans la hiérarchie. Donc
        // si `currentText` a été remplacé pendant qu'on était au menu ou en
        // création (typiquement après "Nouvelle aventure" qui repart de
        // l'intro), `visibleText` reste figé sur l'ancien texte (ex. la fin
        // d'aventure). On resynchronise sans animation à l'apparition pour
        // s'aligner sur l'état courant.
        if visibleText != session.currentText {
            visibleText = session.currentText
        }
    }

    private func flipTo(_ newText: String) {
        guard newText != visibleText else { return }
        // First load: drop straight in, no flip.
        if visibleText.isEmpty {
            visibleText = newText
            return
        }

        flipTask?.cancel()
        let half = Double(flipHalfMs) / 1000.0

        flipTask = Task { @MainActor in
            // 1) Fold the current page towards 90° (edge-on, invisible).
            withAnimation(.easeIn(duration: half)) {
                pageRotation = 90
            }
            try? await Task.sleep(for: .milliseconds(flipHalfMs))
            if Task.isCancelled { return }

            // 2) Swap the text while we're still invisible, and jump to
            //    the opposite edge so the unfold starts from the other side.
            visibleText = newText
            pageRotation = -90

            // 3) Unfold to 0°.
            withAnimation(.easeOut(duration: half)) {
                pageRotation = 0
            }
        }
    }

    // MARK: - Fin d'aventure (stats + boutons)

    private var endingButtons: some View {
        VStack(spacing: 16) {
            EndingStatsView(session: session)
            VStack(spacing: 10) {
                MenuPrimaryButton(label: "Recommencer l'aventure",
                                  icon: "restart_game") {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        session.restart()
                    }
                }
                MenuSecondaryButton(label: "Retour au menu") {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        session.backToMenu()
                    }
                }
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Récap de fin d'aventure

struct EndingStatsView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        VStack(spacing: 14) {
            outcomeHeader
            gradeCard
            statsBlock
        }
    }

    /// Grand bandeau ouvert sur la fin atteinte : titre stylé, accolade
    /// ornementale, et la phrase de blurb de `FinalOutcome`. Sépare visuellement
    /// le moment narratif des chiffres en dessous.
    @ViewBuilder
    private var outcomeHeader: some View {
        if let outcome = session.finalOutcome {
            VStack(spacing: 10) {
                // Pour la mort, on remplace le fleur-de-lys décoratif par
                // l'asset `epitaph` (logo plus marqué pour signaler une
                // épitaphe). Les autres fins (honour / destruction / dark /
                // transcendence) gardent le ⚜ doré.
                if outcome == .death {
                    Theme.icon("epitaph", size: 40, color: Theme.ink)
                } else {
                    Text("⚜")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.oldGold.opacity(0.7))
                }
                Text(outcome.title)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.ink)
                    .multilineTextAlignment(.center)
                    .shadow(color: Theme.oldGold.opacity(0.25), radius: 4, x: 0, y: 1)
                    .lineSpacing(2)
                Rectangle()
                    .fill(Theme.inkFaded.opacity(0.4))
                    .frame(width: 60, height: 0.6)
                Text(outcome.blurb)
                    .font(.system(size: 14, design: .serif))
                    .italic()
                    .foregroundColor(Theme.inkFaded)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.parchmentLight.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.oldGold.opacity(0.45), lineWidth: 0.8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.inkFaded.opacity(0.25), lineWidth: 0.4)
                    .padding(3)
            )
        }
    }

    /// Carte grade + score dans un encart or, déjà existant mais isolé pour
    /// la lisibilité.
    private var gradeCard: some View {
        VStack(spacing: 4) {
            Text(session.gradeTitle)
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)
            Text("\(session.finalScore) points")
                .font(Theme.display(12))
                .foregroundColor(Theme.oldGold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.oldGold.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.oldGold.opacity(0.55), lineWidth: 0.8)
        )
    }

    private var statsBlock: some View {
        VStack(spacing: 8) {
            Text("Récit de ton aventure")
                .font(Theme.display(13))
                .foregroundColor(Theme.inkFaded)
                .padding(.bottom, 4)

            row(icon: "ability",
                tint: Theme.blood,
                label: "Combats remportés",
                value: "\(session.battlesWon)")

            if session.battlesFled > 0 {
                row(icon: "flee",
                    tint: Theme.inkFaded,
                    label: "Combats fuis",
                    value: "\(session.battlesFled)")
            }

            HStack(spacing: 12) {
                Theme.icon("inventory", size: 16, color: Theme.oldGold)
                    .frame(width: 20)
                Text("Objets collectés")
                    .font(Theme.body(14))
                    .foregroundColor(Theme.ink)
                Spacer(minLength: 8)
                Text("\(session.player.items.count)")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.ink)
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                CoinIcon(size: 14).frame(width: 20)
                Text("Pièces d'or restantes")
                    .font(Theme.body(14))
                    .foregroundColor(Theme.ink)
                Spacer(minLength: 8)
                Text("\(session.player.gold)")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.ink)
                    .monospacedDigit()
            }

            row(icon: "life",
                tint: Theme.blood,
                label: "Endurance finale",
                value: "\(max(session.player.stamina, 0)) / \(session.player.staminaMax)")

            row(icon: "luck",
                tint: Theme.verdigris,
                label: "Chance restante",
                value: "\(max(session.player.luck, 0)) / \(session.player.luckMax)")

            // Durée écoulée depuis le premier jet de dés — n'apparaît que
            // si la save courante contient bien un `runStartedAt` (les
            // saves d'avant cette feature n'en ont pas, on évite alors un
            // 0/aberration).
            if let elapsed = session.runDurationText {
                row(icon: "info.circle",
                    tint: Theme.inkFaded,
                    label: "Temps de jeu",
                    value: elapsed)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(0.45), lineWidth: 0.6)
        )
    }

    private func row(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            StatGlyph(icon: icon, color: tint, size: 13)
                .frame(width: 20)
            Text(label)
                .font(Theme.body(14))
                .foregroundColor(Theme.ink)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundColor(Theme.ink)
                .monospacedDigit()
        }
    }
}

// MARK: - Note en marge (effet d'un choix : dégâts, objet trouvé, etc.)

struct MarginNote: View {
    let message: EventMessage

    private var icon: String {
        // Override explicite (ex. message d'item posé avec `get_items`,
        // de coût en or avec `coin`, de bonus stat avec `gain_luck` /
        // `gain_life`) — priorité absolue sur la table par `kind`.
        if let override = message.iconOverride { return override }
        switch message.kind {
        case .gain:    return "sparkles"
        case .heal:    return "heal_up"      // pixel-art : on récupère de la vie
        case .damage:  return "heal_down"    // pixel-art : on perd de la vie
        case .loss:    return "minus.circle.fill"
        case .lucky:   return "star.fill"
        case .unlucky: return "trap"         // pixel-art : piège / mauvaise pioche au jet de Chance
        case .info:    return "circle.fill"
        }
    }

    private var tint: Color {
        switch message.kind {
        case .gain:    return Theme.oldGold
        case .heal:    return Theme.verdigris
        case .damage:  return Theme.blood
        case .loss:    return Theme.oldGold
        case .lucky:   return Theme.oldGold
        case .unlucky: return Theme.blood
        case .info:    return Theme.inkFaded
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Centrage vertical de l'icône avec le texte. Avant on était
            // en `.top` avec un `.padding(.top, 1)` — résultat : sur un
            // message court tenant sur une ligne (la majorité), le texte
            // était collé en haut du chip et laissait une marge vide en
            // dessous (l'icône 20×20 dominait la hauteur de la row).
            // `.center` aligne le texte au milieu vertical du chip ; les
            // rares messages multi-lignes restent acceptables avec
            // l'icône centrée sur le bloc.
            Theme.icon(icon, size: 14, color: tint)
                .frame(width: 20, height: 20)

            Text(message.text)
                .font(Theme.body(14))
                .italic()
                .foregroundColor(Theme.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 0.6)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint.opacity(0.7))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Planche illustrée pleine page

/// Overlay façon "Défis Fantastiques" : l'illustration prend l'écran, le
/// joueur clique "Continuer" pour révéler le passage. Image cherchée dans
/// le bundle sous `illustration_<name>.jpg`. Si absente, on n'affiche que
/// le bouton — l'aventure ne se bloque pas.
struct FullPageIllustration: View {
    let name: String
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.pageBackground

            VStack(spacing: 20) {
                Spacer()

                if let image = Self.loadIllustration(named: name) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .saturation(0)
                        .colorMultiply(Theme.parchmentLight)
                        .overlay(
                            LinearGradient(
                                colors: [.clear, Theme.parchment.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Theme.inkFaded.opacity(0.5), lineWidth: 0.9)
                        )
                        .padding(.horizontal, 24)
                        .scaleEffect(appeared ? 1.0 : 0.96)
                        .opacity(appeared ? 1.0 : 0)
                }

                Spacer()

                Button(action: onDismiss) {
                    HStack(spacing: 10) {
                        Text("Continuer")
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
                .opacity(appeared ? 1.0 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                appeared = true
            }
        }
    }

    /// Cherche d'abord `illustration_<name>.jpg` (convention NPC / scène).
    /// Fallback sur `<name>.jpg` (convention historique des portraits de
    /// monstres — `tomb_basilisk.jpg`, `forest_wolves.jpg`, etc.) pour
    /// pouvoir réutiliser ces fichiers comme planches avant-combat sans
    /// avoir à les renommer. Dernier filet : si le nom finit par `_phase<N>`
    /// (cas des combats multi-phases comme Mortimer), on retire le suffixe
    /// et on retente — comme ça `mortimer_spectre_phase2` retombe sur
    /// `mortimer_spectre.jpg` sans qu'il faille dupliquer le fichier.
    private static func loadIllustration(named name: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: "illustration_\(name)",
                                      withExtension: "jpg"),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        if let stripped = stripPhaseSuffix(name), stripped != name {
            return loadIllustration(named: stripped)
        }
        return nil
    }

    /// Retire un suffixe `_phase<N>` si présent. Renvoie nil sinon.
    private static func stripPhaseSuffix(_ name: String) -> String? {
        guard let range = name.range(of: #"_phase\d+$"#, options: .regularExpression) else {
            return nil
        }
        return String(name[..<range.lowerBound])
    }
}

struct IllustrationContinueStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Theme.ink)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.parchmentLight.opacity(configuration.isPressed ? 0.95 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.inkFaded.opacity(0.65), lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}

// MARK: - Bandeau de chapitre

/// Petite vignette de paysage gravé + libellé du chapitre, affichée en
/// tête de page. Le visuel est désaturé et teinté parchemin pour rester
/// dans la palette du livre. Si l'image n'est pas trouvée, on retombe
/// proprement sur l'ancien rendu texte uniquement.
struct ChapterBanner: View {
    let chapter: Chapter

    var body: some View {
        VStack(spacing: 4) {
            if let image = Self.loadBanner(named: chapter.bannerImageName) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .saturation(0)
                    .colorMultiply(Theme.parchmentLight)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Theme.parchment.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Theme.inkFaded.opacity(0.4), lineWidth: 0.6)
                    )
                    .padding(.horizontal, 8)
            }
            Text(chapter.title)
                .font(Theme.display(11))
                .foregroundColor(Theme.inkFaded.opacity(0.85))
        }
    }

    private static func loadBanner(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let img = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return img
    }
}

// MARK: - Liste de choix

struct ChoicesList: View {
    let choices: [Choice]
    /// Solde courant — passé à chaque `ChoiceButton` pour décider du
    /// grisage des options payantes.
    let playerGold: Int
    let onChoose: (Choice) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(choices) { choice in
                ChoiceButton(choice: choice,
                             playerGold: playerGold) { onChoose(choice) }
            }
        }
        .padding(.top, 8)
    }
}

/// Bouton qui remplace la liste des choix quand l'aventure attend un jet
/// de Chance déclenché par le joueur. Visuel distinct (icône dé doré +
/// fond ambré) pour signaler que ce n'est pas un choix narratif ordinaire.
struct LuckPromptButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icône principale : asset pixel-art `try_luck` (avant : dé
                // SF Symbol). Représente l'action "Tenter sa Chance".
                Theme.icon("try_luck", size: 18, color: Theme.oldGold)
                Text(label)
                    .font(Theme.display(15))
                    .foregroundColor(Theme.ink)
                Spacer(minLength: 0)
                // Étincelles décoratives à droite — restent en SF Symbol :
                // c'est une fioriture visuelle, pas une icône fonctionnelle.
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.oldGold.opacity(0.7))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(LuckPromptButtonStyle())
        .padding(.top, 8)
    }
}

struct LuckPromptButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.oldGold.opacity(configuration.isPressed ? 0.30 : 0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.oldGold.opacity(0.6), lineWidth: 0.9)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}

struct ChoiceButton: View {
    let choice: Choice
    /// Solde du joueur — sert à savoir si une option payante est accessible.
    let playerGold: Int
    let action: () -> Void

    private var isUnaffordable: Bool {
        if let price = choice.priceGold, price > playerGold { return true }
        return false
    }

    /// Nom de l'asset pixel-art à afficher pour un choix normal (non-★).
    /// Priorité de détection : retour (le plus spécifique) > dialogue >
    /// classique. L'ordre matters parce que par exemple « Revenir parler à
    /// la veuve » serait classé en retour, pas en dialogue.
    private var choiceIconName: String {
        if isReturn { return "return_option" }
        if isDialogue { return "dialogue_option" }
        return "classic_option"
    }

    /// Détection heuristique : le choix invite-t-il à un dialogue ?
    /// On regarde si le texte commence par un verbe de parole — couvre la
    /// quasi-totalité des PNJ du jeu sans avoir à étiqueter chaque option
    /// dans le `.ink`. Les options spéciales (★) gardent leur losange or.
    private var isDialogue: Bool {
        guard !choice.isSpecial else { return false }
        let trimmed = choice.text.trimmingCharacters(in: .whitespaces).lowercased()
        let dialogueOpeners = [
            "saluer", "parler", "demander", "discuter", "interroger",
            "répondre", "lui demander", "lui parler", "lui glisser",
            "le saluer", "la saluer", "lui dire",
            "lui offrir une pièce", "le remercier", "le supplier",
            "murmurer", "écouter"
        ]
        return dialogueOpeners.contains { trimmed.hasPrefix($0) }
    }

    /// Détection heuristique : le choix mène-t-il à un retour vers un hub
    /// (place du village, ruelles, clairière, carrefour…) ? Verbes types :
    /// « Retour / Revenir / Remonter / Reprendre la piste / Repartir ».
    private var isReturn: Bool {
        guard !choice.isSpecial else { return false }
        let trimmed = choice.text.trimmingCharacters(in: .whitespaces).lowercased()
        let returnOpeners = [
            "retour", "revenir", "remonter", "remonte",
            "reprendre la piste", "reprendre les ruelles",
            "repartir", "retourner", "retourne",
            "te ressaisir", "te recueillir",
            "souffler un coup", "redescendre"
        ]
        return returnOpeners.contains { trimmed.hasPrefix($0) }
    }

    var body: some View {
        Button(action: { if !isUnaffordable { action() } }) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if choice.isSpecial {
                    // Option spéciale (★ dans le .ink) — asset pixel-art
                    // `item_option` (clé / parchemin). Signale les chemins
                    // débloqués par un item ramassé ailleurs.
                    Theme.icon("item_option", size: 14, color: Theme.oldGold)
                } else {
                    // Choix normal : asset pixel-art selon le type d'action.
                    //   - retour vers un hub → return_option
                    //   - dialogue → dialogue_option
                    //   - autre → classic_option
                    Theme.icon(choiceIconName,
                               size: 14,
                               color: Theme.oldGold)
                }
                Text(choice.text)
                    .font(Theme.body(16))
                    .foregroundColor(Theme.ink)
                    .italic(choice.isSpecial)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ChoiceButtonStyle(isSpecial: choice.isSpecial,
                                       isUnaffordable: isUnaffordable))
        .disabled(isUnaffordable)
        .accessibilityHint(isUnaffordable ? "Bourse insuffisante" : "")
    }
}

struct ChoiceButtonStyle: ButtonStyle {
    let isSpecial: Bool
    /// True quand l'option est payante mais que le joueur n'a pas assez. On
    /// l'affiche quand même (le joueur voit qu'il aurait pu) mais grisée
    /// et inactive.
    var isUnaffordable: Bool = false

    private var baseFill: Color {
        if isUnaffordable { return Theme.parchmentLight.opacity(0.25) }
        return isSpecial ? Theme.oldGold.opacity(0.14) : Theme.parchmentLight.opacity(0.55)
    }

    private var pressedFill: Color {
        isSpecial ? Theme.oldGold.opacity(0.30) : Theme.parchmentLight.opacity(0.95)
    }

    private var strokeColor: Color {
        if isUnaffordable { return Theme.inkFaded.opacity(0.30) }
        return isSpecial ? Theme.oldGold.opacity(0.55) : Theme.inkFaded.opacity(0.55)
    }

    private var strokeWidth: CGFloat {
        isSpecial ? 0.9 : 0.6
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isPressed ? pressedFill : baseFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .opacity(isUnaffordable ? 0.45 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - HUD du jeu (unifié exploration + combat)

/// Barre de statut unique qui couvre les deux contextes :
///   - **Exploration** : chip chapitre + stats + or + inventaire + menu.
///     `chapter` non-nil, `showsResourcesAndInventory` true, `isInCombat`
///     false, `anticipatedDamage` 0.
///   - **Combat** : stats + menu uniquement, jauge avec dégât anticipé,
///     réactions de hit (flash, shake, particules, floater). `chapter` nil
///     (le combat est intemporel, le chapitre est masqué pour libérer de
///     la place), `showsResourcesAndInventory` false, `isInCombat` true.
///
/// L'ancien duo `StatsHUD` + `CompactBattleHUD` dupliquait stats, fleurons,
/// menu button, jauge. Un seul struct = une seule source de vérité visuelle.
struct GameHUD: View {
    let player: PlayerState
    /// Si fourni → chip chapitre au-dessus du HUD. Nil → pas de chip
    /// (utilisé en combat).
    let chapter: Chapter?
    /// Dégât que l'ennemi infligerait sur un hit ce round (2 + damageBonus).
    /// 0 = pas de preview (hors combat).
    let anticipatedDamage: Int
    /// Si true, affiche le compteur d'or + le bouton inventaire. Désactivé
    /// en combat (pas d'achat en pleine baston, et pour l'inventaire un
    /// bouton dédié vit dans la BattleView).
    let showsResourcesAndInventory: Bool
    /// Active les réactions visuelles d'encaissement : flash rouge, shake,
    /// particules, floating damage à droite. Hors combat les changements
    /// d'Endurance restent visibles via le +N/-N de `StatBadge`, mais
    /// pas de feedback "visceral" — l'exploration est calme par nature.
    let isInCombat: Bool
    let consumableCount: Int
    let inventoryPulseTrigger: Int
    /// Nombre de potions utilisées dans la run. Affiché en chip discret à
    /// côté du chip chapitre, surtout utile pour les joueurs visant le
    /// succès « Iron-man » (0 potion) — ils gardent un œil sur leur compteur.
    let potionsUsed: Int
    let onOpenInventory: () -> Void
    let onReturnToMenu: () -> Void

    // États transitoires des réactions de hit. Inertes hors combat.
    @State private var lastStamina: Int = -1
    @State private var staminaFloater: StaminaFloater? = nil
    @State private var hitFlash: Bool = false
    @State private var hitShakeOffset: CGFloat = 0
    @State private var hitParticleTrigger: UUID = UUID()
    @State private var showHitParticles: Bool = false

    private var staminaRatio: Double {
        guard player.staminaMax > 0 else { return 0 }
        return Swift.min(1.0, Double(Swift.max(player.stamina, 0)) / Double(player.staminaMax))
    }

    /// Ratio de la zone « à risque » sur la jauge : du point
    /// `(stamina − anticipatedDamage)` jusqu'au point `stamina`. Si la
    /// stamina actuelle est inférieure ou égale au dégât anticipé, la
    /// zone à risque couvre toute la portion remplie (= le prochain coup
    /// peut tuer).
    private var dangerStartRatio: Double {
        guard player.staminaMax > 0, anticipatedDamage > 0 else { return staminaRatio }
        let dangerStart = max(0, player.stamina - anticipatedDamage)
        return Double(dangerStart) / Double(player.staminaMax)
    }

    var body: some View {
        VStack(spacing: 4) {
            if let chapter {
                HStack(spacing: 8) {
                    chapterChip(chapter)
                    Spacer(minLength: 0)
                    potionsChip
                }
            }
            statsCard
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.blood.opacity(hitFlash ? 0.18 : 0))
                )
                .offset(x: hitShakeOffset)
                .overlay(alignment: .topTrailing) {
                    if let floater = staminaFloater {
                        FloatingDamage(value: floater.value)
                            .id(floater.id)
                            .padding(.trailing, 60)
                            .padding(.top, 8)
                    }
                }
                .overlay(alignment: .center) {
                    if showHitParticles {
                        HitParticles(tint: Theme.blood)
                            .id(hitParticleTrigger)
                            .offset(y: 16)
                    }
                }
        }
        .onAppear { lastStamina = player.stamina }
        .onChange(of: player.stamina) { oldValue, newValue in
            // Réactions de hit uniquement en combat — en exploration, le
            // +/-N de StatBadge suffit (un coup de vapeur toxique dans la
            // crypte ne mérite pas un shake d'écran).
            guard isInCombat else { return }
            let delta = newValue - oldValue
            if delta < 0 {
                triggerHit()
                hitParticleTrigger = UUID()
                showHitParticles = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showHitParticles = false
                }
            }
            if delta != 0 {
                staminaFloater = StaminaFloater(value: delta)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if staminaFloater?.value == delta {
                        staminaFloater = nil
                    }
                }
            }
            lastStamina = newValue
        }
    }

    /// Chip chapitre — petit fleuron + nom court + fleuron, en small caps
    /// dorées au-dessus du cadre du HUD. Subtil mais toujours présent.
    private func chapterChip(_ chapter: Chapter) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 5))
                .foregroundColor(Theme.oldGold.opacity(0.7))
            Text(chapter.shortTitle.uppercased())
                .font(Theme.display(10))
                .tracking(1.8)
                .foregroundColor(Theme.oldGold)
                .shadow(color: Theme.ink.opacity(0.5), radius: 2, x: 0, y: 1)
            Image(systemName: "diamond.fill")
                .font(.system(size: 5))
                .foregroundColor(Theme.oldGold.opacity(0.7))
        }
    }

    /// Mini-compteur de potions utilisées dans la run. Discret, en marge
    /// droite de la rangée chapitre. Aide les joueurs visant l'Iron-man
    /// (0 potion) à savoir où ils en sont sans avoir à fouiller dans des
    /// stats. Couleur verdâtre quand encore à 0 (pur), grise sinon.
    private var potionsChip: some View {
        HStack(spacing: 4) {
            Theme.icon("green_potion",
                       size: 10,
                       color: potionsUsed == 0 ? Theme.verdigris : Theme.inkFaded)
            Text("\(potionsUsed)")
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .foregroundColor(potionsUsed == 0 ? Theme.verdigris : Theme.inkFaded)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(potionsUsed) potion\(potionsUsed > 1 ? "s" : "") utilisée\(potionsUsed > 1 ? "s" : "")")
    }

    private var statsCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                StatBadge(icon: "ability",
                          value: player.skill, max: player.skillMax,
                          color: Theme.inkBlue,
                          criticalThreshold: nil,
                          accessibility: "Habileté",
                          showsMax: false)
                fleuronDivider
                StatBadge(icon: "life",
                          value: player.stamina, max: player.staminaMax,
                          color: Theme.blood,
                          criticalThreshold: max(1, player.staminaMax / 4),
                          accessibility: "Endurance")
                fleuronDivider
                StatBadge(icon: "luck",
                          value: player.luck, max: player.luckMax,
                          color: Theme.verdigris,
                          criticalThreshold: 3,
                          accessibility: "Chance")
                Spacer(minLength: 4)
                if showsResourcesAndInventory {
                    actionGroupSeparator
                    goldResource
                    actionGroupSeparator
                    inventoryButton
                }
                menuButton
            }
            // Jauge d'Endurance — 3 couches :
            //   1. track parchemin foncé
            //   2. Endurance courante (rouge)
            //   3. Zone "à risque" du round courant (ink sombre par-dessus
            //      le rouge), uniquement quand `anticipatedDamage > 0`.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.parchmentDark.opacity(0.5))
                    Capsule()
                        .fill(Theme.blood.opacity(0.85))
                        .frame(width: geo.size.width * staminaRatio)
                        .animation(.easeOut(duration: 0.5), value: staminaRatio)
                    if anticipatedDamage > 0 && player.stamina > 0 {
                        Capsule()
                            .fill(Theme.ink.opacity(0.55))
                            .frame(width: geo.size.width * (staminaRatio - dangerStartRatio))
                            .offset(x: geo.size.width * dangerStartRatio)
                            .animation(.easeOut(duration: 0.5), value: dangerStartRatio)
                    }
                }
            }
            .frame(height: isInCombat ? 5 : 4)
        }
        .ornamentedHudFrame()
    }

    /// Flash + shake quand le joueur encaisse (combat uniquement).
    private func triggerHit() {
        withAnimation(.easeOut(duration: 0.12)) { hitFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeIn(duration: 0.25)) { hitFlash = false }
        }
        let amplitudes: [(CGFloat, Double)] = [
            (-8, 0.05), (8, 0.05),
            (-5, 0.05), (5, 0.05),
            (0,  0.05)
        ]
        var delay: Double = 0
        for (amp, dur) in amplitudes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: dur)) { hitShakeOffset = amp }
            }
            delay += dur
        }
    }

    private var actionGroupSeparator: some View {
        Rectangle()
            .fill(Theme.inkFaded.opacity(0.35))
            .frame(width: 0.6, height: 18)
            .padding(.horizontal, 4)
    }

    private var menuButton: some View {
        Button(action: onReturnToMenu) {
            Theme.icon("menu", size: 13, color: Theme.parchmentLight)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HudIconButtonStyle(isActive: true))
        .accessibilityLabel("Retour au menu principal")
    }

    private var goldResource: some View {
        HStack(spacing: 4) {
            CoinIcon(size: 12)
            Text("\(player.gold)")
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundColor(Theme.ink)
        }
    }

    private var inventoryButton: some View {
        InventoryHUDButton(
            consumableCount: consumableCount,
            pulseTrigger: inventoryPulseTrigger,
            action: onOpenInventory
        )
    }

    /// Petit fleuron servant de séparateur entre les badges de stats.
    private var fleuronDivider: some View {
        VStack(spacing: 2) {
            Text("◆")
                .font(.system(size: 6))
                .foregroundColor(Theme.inkFaded.opacity(0.55))
        }
        .frame(width: 10)
    }
}

// MARK: - Overlays + utilities extraits
//
// `ChapterTransitionOverlay`, `DeathCinematicOverlay`, `CriticalHealthVignette`,
// `StaminaFloater`, `HitParticles`, `FloatingDamage` ont été déplacés dans
// `tomb/Views/Overlays.swift` pour alléger ce fichier. Voir là-bas.
//
// `CompactBattleHUD` et `StatsHUD` ont été fusionnés en `GameHUD` (plus
// haut dans ce fichier) — un seul struct paramétré par contexte
// (exploration/combat) pour éviter la duplication et garantir qu'une
// modif visuelle se propage partout.

// `StatBadge`, `StatTooltipKind` et `StatTooltipCard` ont été extraits
// dans `tomb/Views/StatBadgeView.swift`.

// MARK: - Bouton inventaire avec badge + pulse

/// Bouton d'inventaire dans le HUD. Affiche la bourse, ajoute un petit
/// badge numérique en haut-droit quand le sac contient des consommables,
/// et pulse brièvement (halo doré + scale) quand le joueur vient d'en
/// ramasser un. C'est ce qui rend l'inventaire "présent" sans le déplacer.
struct InventoryHUDButton: View {
    let consumableCount: Int
    let pulseTrigger: Int
    let action: () -> Void

    /// Bool transitoire piloté par `.onChange(pulseTrigger)`. Quand il
    /// bascule à true, on lance scale + halo ; on revient à false après
    /// ~1.5 s pour pouvoir replulser.
    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    // Halo doré qui apparaît sur le pulse
                    Circle()
                        .fill(Theme.oldGold.opacity(isPulsing ? 0.45 : 0))
                        .blur(radius: 4)
                        .frame(width: 36, height: 36)

                    Theme.icon("inventory", size: 16, color: Theme.inkFaded)
                }
                .scaleEffect(isPulsing ? 1.18 : 1.0)
                .frame(width: 28, height: 28)

                if consumableCount > 0 {
                    badge
                        .offset(x: 6, y: -4)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(HudIconButtonStyle(isActive: true))
        .accessibilityLabel(consumableCount > 0
            ? "Ouvrir l'inventaire — \(consumableCount) consommable\(consumableCount > 1 ? "s" : "")"
            : "Ouvrir l'inventaire")
        .onChange(of: pulseTrigger) { _, _ in
            runPulse()
        }
    }

    /// Chip rouge avec le nombre de consommables disponibles. Petit, posé
    /// en débord pour rester lisible sur la bordure du HUD.
    private var badge: some View {
        Text("\(consumableCount)")
            .font(.system(size: 9, weight: .bold, design: .serif))
            .foregroundColor(Theme.parchmentLight)
            .monospacedDigit()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(minWidth: 14, minHeight: 14)
            .background(
                Capsule().fill(Theme.blood)
            )
            .overlay(
                Capsule().stroke(Theme.parchmentLight.opacity(0.7), lineWidth: 0.5)
            )
    }

    private func runPulse() {
        withAnimation(.easeOut(duration: 0.18)) {
            isPulsing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeIn(duration: 1.0)) {
                isPulsing = false
            }
        }
    }
}

// MARK: - ButtonStyle pour les boutons du HUD

/// Bouton compact pour les actions d'inventaire (Utiliser / Équiper).
/// Style : pavé teinté plein avec parchemin clair en texte, contour ink.
struct InventoryActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Theme.parchmentLight)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 1.0 : 0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.ink.opacity(0.55), lineWidth: 0.7)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}

struct HudIconButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isActive ? Theme.inkFaded : Theme.inkFaded.opacity(0.4))
            .background(
                Circle()
                    .fill(Theme.parchmentLight.opacity(configuration.isPressed ? 0.7 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}

// `InventoryView`, `ResourceCard`, `PouchIcon`, `CoinIcon`, `InventoryRow`
// ont été extraits dans `tomb/Views/InventoryView.swift`.


#Preview {
    ContentView()
}
