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
            if let illustration = session.pendingIllustration {
                FullPageIllustration(name: illustration) {
                    session.dismissIllustration()
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
        }
        .animation(.easeInOut(duration: 0.35), value: session.hasStarted)
        .animation(.easeInOut(duration: 0.35), value: session.isCreatingCharacter)
        .animation(.easeIn(duration: 0.35), value: passageRevealed)
        .sheet(isPresented: $showingInventory) {
            InventoryView(session: session)
        }
        .confirmationDialog(
            "Quitter l'aventure ?",
            isPresented: $showingMenuConfirm,
            titleVisibility: .visible
        ) {
            // `role: .destructive` colore le bouton « Oui » en rouge système
            // (la couleur destructive iOS) — exactement ce qu'on veut pour
            // dire « attention, action sortante ».
            Button("Oui", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    session.backToMenu()
                }
            }
            Button("Non", role: .cancel) {}
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
                CompactBattleHUD(
                    player: session.player,
                    onReturnToMenu: { showingMenuConfirm = true }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            } else {
                StatsHUD(
                    player: session.player,
                    audio: audio,
                    consumableCount: consumableCount,
                    inventoryPulseTrigger: session.inventoryPulse,
                    onOpenInventory: { showingInventory = true },
                    onReturnToMenu: { showingMenuConfirm = true }
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
                            .rotation3DEffect(.degrees(pageRotation),
                                              axis: (x: 0, y: 1, z: 0),
                                              anchor: .center,
                                              perspective: 0.4)
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
                                  icon: "arrow.counterclockwise") {
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
                Text("⚜")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.oldGold.opacity(0.7))
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
                row(icon: "figure.run",
                    tint: Theme.inkFaded,
                    label: "Combats fuis",
                    value: "\(session.battlesFled)")
            }

            HStack(spacing: 12) {
                PouchIcon(size: 16, tint: Theme.oldGold).frame(width: 20)
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
        switch message.kind {
        case .gain:    return "sparkles"
        case .heal:    return "heal_up"      // pixel-art : on récupère de la vie
        case .damage:  return "heal_down"    // pixel-art : on perd de la vie
        case .loss:    return "minus.circle.fill"
        case .lucky:   return "star.fill"
        case .unlucky: return "exclamationmark.triangle.fill"
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
        HStack(alignment: .top, spacing: 12) {
            // Theme.icon(...) intercepte "heart.fill" pour utiliser l'asset
            // pixel-art ; les autres SF Symbols passent normalement.
            Theme.icon(icon, size: 14, color: tint)
                .frame(width: 20, height: 20)
                .padding(.top, 1)

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

    var body: some View {
        Button(action: { if !isUnaffordable { action() } }) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(choice.isSpecial ? "❖" : "✦")
                    .font(.system(size: 14, weight: choice.isSpecial ? .semibold : .regular))
                    .foregroundColor(Theme.oldGold)
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

// MARK: - HUD des statistiques

struct StatsHUD: View {
    let player: PlayerState
    @ObservedObject var audio: AmbientAudio
    /// Compteur de consommables actuellement dans le sac (potions, herbes,
    /// viande). Affiché en badge sur le bouton inventaire.
    let consumableCount: Int
    /// Trigger qui s'incrémente à chaque pickup de consommable — déclenche
    /// la pulsation du bouton inventaire pour signaler "il y a un truc neuf
    /// à boire".
    let inventoryPulseTrigger: Int
    let onOpenInventory: () -> Void
    let onReturnToMenu: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            StatBadge(icon: "ability",
                      value: player.skill, max: player.skillMax,
                      color: Theme.inkBlue,
                      criticalThreshold: nil,
                      accessibility: "Habileté")
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
            goldResource
            inventoryButton
            audioToggle
            menuButton
        }
        .ornamentedHudFrame()
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

    private var audioToggle: some View {
        // `isPlaying` ne reflète que le drone d'ambiance. On préfère regarder
        // les deux préférences (ambiance + effets) pour que l'icône soit
        // cohérente avec ce que le bouton fait — couper TOUT.
        let anyAudio = audio.ambientEnabled || audio.effectsEnabled
        return Button {
            audio.toggle()
        } label: {
            Group {
                if anyAudio {
                    // Asset pixel-art custom quand le son est actif.
                    Theme.icon("sound", size: 13, color: Theme.parchmentLight)
                } else {
                    // Couper le son : SF Symbol explicite (haut-parleur
                    // barré). On garde le système pour le différencier
                    // visuellement du PNG actif sans avoir besoin d'un
                    // deuxième asset "sound off".
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 13))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(HudIconButtonStyle(isActive: anyAudio))
        .accessibilityLabel(anyAudio ? "Couper le son" : "Réactiver le son")
    }

    /// Petit fleuron servant de séparateur entre les badges de stats. Plus
    /// "grimoire" qu'un trait vertical : un losange filiforme avec une fine
    /// barre verticale traversante, suggérant un repère de copiste.
    private var fleuronDivider: some View {
        VStack(spacing: 2) {
            Text("◆")
                .font(.system(size: 6))
                .foregroundColor(Theme.inkFaded.opacity(0.55))
        }
        .frame(width: 10)
    }

}

// MARK: - HUD compact pour le mode combat

/// Version dégraissée du HUD utilisée uniquement pendant un combat.
/// Ne montre que les 3 stats vitales (Habileté, Endurance, Chance) et
/// un bouton "maison" pour sortir vers le menu. Les ressources et boutons
/// qui n'ont pas d'usage en combat (or, audio, inventaire) sont masqués
/// pour libérer de la place à l'action.
/// Vignette rouge sang qui pulse sur les bords de l'écran quand le joueur
/// passe sous 25% d'Endurance en combat. Stress visuel immédiat sans
/// masquer le contenu central.
struct CriticalHealthVignette: View {
    @State private var pulse: Bool = false

    var body: some View {
        RadialGradient(
            colors: [
                .clear,
                Theme.blood.opacity(pulse ? 0.40 : 0.20)
            ],
            center: .center,
            startRadius: 220,
            endRadius: 520
        )
        .blendMode(.multiply)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Marqueur ±N qui monte et s'éteint sur une jauge quand stamina varie.
/// Utilisé à la fois sur le HUD joueur et la carte d'ennemi pour donner
/// un retour visuel viscéral aux coups.
struct StaminaFloater: Equatable {
    let value: Int
    let id = UUID()
}

/// Petite gerbe de particules qui jaillissent depuis un point quand on
/// reçoit un coup. ~5 éclats projetés perpendiculairement avec un offset
/// random + fade en ~450 ms. Une fois disparus, la view se rend
/// transparente — à instancier avec un `.id()` qui change pour rejouer.
struct HitParticles: View {
    /// Teinte des éclats. Rouge sang pour dégât, doré pour effet bénéfique.
    var tint: Color = Theme.blood

    @State private var progress: CGFloat = 0
    private let count = 5
    private let amplitudes: [CGSize]

    init(tint: Color = Theme.blood, seed: Int = 0) {
        self.tint = tint
        var rng = SystemRandomNumberGenerator()
        let amps: [CGSize] = (0..<5).map { _ in
            let dx = CGFloat(Int.random(in: -22...22, using: &rng))
            let dy = CGFloat(Int.random(in: -20...4, using: &rng))
            return CGSize(width: dx, height: dy)
        }
        self.amplitudes = amps
    }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { idx in
                Circle()
                    .fill(tint.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .offset(
                        x: amplitudes[idx].width * progress,
                        y: amplitudes[idx].height * progress
                    )
                    .opacity(1.0 - Double(progress))
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                progress = 1
            }
        }
    }
}

/// Texte flottant qui apparaît puis monte de quelques points en perdant
/// son opacité. Auto-disparition après ~900 ms.
struct FloatingDamage: View {
    let value: Int

    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 1

    private var tint: Color {
        value < 0 ? Theme.blood : Theme.verdigris
    }

    var body: some View {
        Text(value > 0 ? "+\(value)" : "\(value)")
            .font(.system(size: 18, weight: .bold, design: .serif))
            .foregroundColor(tint)
            .shadow(color: Theme.parchmentLight, radius: 1)
            .monospacedDigit()
            .opacity(opacity)
            .offset(y: offsetY)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9)) {
                    offsetY = -28
                    opacity = 0
                }
            }
            .allowsHitTesting(false)
    }
}

struct CompactBattleHUD: View {
    let player: PlayerState
    let onReturnToMenu: () -> Void

    /// Dernière Endurance observée — sert à calculer le delta pour afficher
    /// un chiffre flottant ±N quand stamina change.
    @State private var lastStamina: Int = -1
    /// Floater actif : la valeur (>0 = soin, <0 = dégât) et un id pour
    /// forcer la recréation de la vue à chaque trigger.
    @State private var staminaFloater: StaminaFloater? = nil
    /// Flash rouge bref + offset horizontal quand on encaisse — même
    /// langage visuel que l'EnemyCard côté ennemi.
    @State private var hitFlash: Bool = false
    @State private var hitShakeOffset: CGFloat = 0
    /// Trigger pour rejouer la gerbe de particules à chaque hit. `.id()`
    /// lié à cette valeur force la recréation de la HitParticles view.
    @State private var hitParticleTrigger: UUID = UUID()
    @State private var showHitParticles: Bool = false

    private var staminaRatio: Double {
        guard player.staminaMax > 0 else { return 0 }
        return Double(max(player.stamina, 0)) / Double(player.staminaMax)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                StatBadge(icon: "ability",
                          value: player.skill, max: player.skillMax,
                          color: Theme.inkBlue,
                          criticalThreshold: nil,
                          accessibility: "Habileté")
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
                Button(action: onReturnToMenu) {
                    Theme.icon("menu", size: 13, color: Theme.parchmentLight)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HudIconButtonStyle(isActive: true))
                .accessibilityLabel("Retour au menu principal")
            }
            // Jauge d'Endurance — même langage visuel que l'EnemyCard, pour
            // qu'on lise d'un coup d'œil les deux barres face à face.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.parchmentDark.opacity(0.5))
                    Capsule()
                        .fill(Theme.blood.opacity(0.85))
                        .frame(width: geo.size.width * staminaRatio)
                        .animation(.easeOut(duration: 0.5), value: staminaRatio)
                }
            }
            .frame(height: 5)
        }
        .ornamentedHudFrame()
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
                    .offset(y: 16)  // au niveau de la jauge
            }
        }
        .onAppear { lastStamina = player.stamina }
        .onChange(of: player.stamina) { oldValue, newValue in
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

    /// Réplique de la logique `EnemyCard.triggerHit()` pour le HUD joueur :
    /// flash rouge bref + shake horizontal sec. Visuel cohérent des deux
    /// côtés de l'écran (le joueur encaisse comme l'ennemi encaisse).
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

    /// Petit fleuron servant de séparateur entre les badges de stats. Plus
    /// "grimoire" qu'un trait vertical : un losange filiforme avec une fine
    /// barre verticale traversante, suggérant un repère de copiste.
    private var fleuronDivider: some View {
        VStack(spacing: 2) {
            Text("◆")
                .font(.system(size: 6))
                .foregroundColor(Theme.inkFaded.opacity(0.55))
        }
        .frame(width: 10)
    }
}

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

    @State private var pulse: Bool = false

    private var isCritical: Bool {
        guard let threshold = criticalThreshold else { return false }
        return value <= threshold && value > 0
    }

    var body: some View {
        VStack(spacing: 2) {
            StatGlyph(icon: icon, color: color.opacity(0.75), size: 11)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(color)
                Text("/\(max)")
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .foregroundColor(Theme.inkFaded)
            }
        }
        .frame(minWidth: 38)
        .opacity(isCritical && pulse ? 0.55 : 1.0)
        .scaleEffect(isCritical && pulse ? 0.96 : 1.0)
        .onAppear { syncPulse() }
        .onChange(of: isCritical) { _, _ in syncPulse() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibility) \(value) sur \(max)")
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

// MARK: - Inventaire (sheet)

struct InventoryView: View {
    @ObservedObject var session: GameSession
    @Environment(\.dismiss) private var dismiss

    /// Phrase courte expliquant pourquoi un consommable est inutilisable
    /// dans l'état actuel — affichée sous le bouton grisé.
    private func consumableWasteReason(for effect: ConsumableEffect) -> String {
        switch effect {
        case .heal:        return "Endurance déjà au maximum"
        case .restoreLuck: return "Chance déjà au maximum"
        case .boostSkillNextAttack, .weakenEnemyNextAttack:
            return "À utiliser pendant un combat"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground
                ScrollView {
                    VStack(spacing: 16) {
                        ResourceCard(gold: session.player.gold)
                        if session.player.items.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(Array(session.player.items).sorted(), id: \.self) { itemId in
                                    let info = ItemCatalog.all[itemId]
                                    let isWeapon = info?.weapon != nil
                                    let isEquipped = session.player.equippedWeapon == itemId
                                    // Un consommable n'est proposable que s'il aurait
                                    // un effet réel (pas un soin à PV pleins, pas de
                                    // restore de Chance déjà au max).
                                    let useful = info?.consumable.map(session.isUseful(effect:)) ?? false
                                    InventoryRow(
                                        itemId: itemId,
                                        isEquipped: isEquipped,
                                        useDisabledReason: (info?.consumable != nil && !useful)
                                            ? consumableWasteReason(for: info!.consumable!)
                                            : nil,
                                        onUse: useful
                                            ? { session.useItem(itemId) }
                                            : nil,
                                        onEquip: (isWeapon && !isEquipped)
                                            ? { session.equipWeapon(itemId) }
                                            : nil,
                                        onUnequip: (isWeapon && isEquipped)
                                            ? { session.unequipWeapon() }
                                            : nil
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Inventaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(Theme.ink)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Theme.icon("inventory", size: 28, color: Theme.inkFaded.opacity(0.6))
            Text("Ton sac est vide pour l'instant.")
                .font(Theme.body(14))
                .italic()
                .foregroundColor(Theme.inkFaded)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
}

/// Petite carte "Or" en tête d'inventaire. L'or apparaît déjà dans le HUD
/// mais reste affiché ici pour rester visible quand le sac est ouvert.
struct ResourceCard: View {
    let gold: Int

    var body: some View {
        HStack(spacing: 10) {
            CoinIcon(size: 18)
            Text("\(gold)")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(Theme.ink)
                .monospacedDigit()
            Text("pièce\(gold > 1 ? "s" : "") d'or")
                .font(Theme.display(11))
                .foregroundColor(Theme.inkFaded)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
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
}

/// Bourse à cordons : silhouette de pochette en cuir resserrée par une
/// ficelle, façon "bourse d'or" d'aventurier. Pas de SF Symbol équivalent,
/// donc on la dessine à la main. Utilisée comme icône d'inventaire dans
/// le HUD et dans le récap de fin de partie.
struct PouchIcon: View {
    var size: CGFloat = 14
    var tint: Color = Theme.ink

    var body: some View {
        Canvas { ctx, _ in
            let w = size
            let h = size
            // Bordure / corps : forme arrondie qui s'évase vers le bas,
            // resserrée en haut comme une bourse fermée. Construite à la
            // main avec deux courbes de Bézier symétriques.
            let body = Path { p in
                let neckLeft  = CGPoint(x: w * 0.32, y: h * 0.32)
                let neckRight = CGPoint(x: w * 0.68, y: h * 0.32)
                let leftBelly = CGPoint(x: w * 0.05, y: h * 0.70)
                let bottom    = CGPoint(x: w * 0.50, y: h * 0.98)
                let rightBelly = CGPoint(x: w * 0.95, y: h * 0.70)

                p.move(to: neckLeft)
                p.addQuadCurve(to: leftBelly,
                               control: CGPoint(x: w * 0.02, y: h * 0.45))
                p.addQuadCurve(to: bottom,
                               control: CGPoint(x: w * 0.05, y: h * 1.02))
                p.addQuadCurve(to: rightBelly,
                               control: CGPoint(x: w * 0.95, y: h * 1.02))
                p.addQuadCurve(to: neckRight,
                               control: CGPoint(x: w * 0.98, y: h * 0.45))
                p.closeSubpath()
            }
            ctx.fill(body, with: .color(tint))

            // Cordon : trait horizontal traversant le col, avec deux petits
            // brins qui retombent. Inscrit en couleur "encre" plus claire
            // pour rester lisible sur la pochette.
            let stringColor = tint.opacity(0.55)
            let stringWidth = max(0.8, w * 0.08)
            let neckY = h * 0.30
            let cord = Path { p in
                p.move(to: CGPoint(x: w * 0.22, y: neckY))
                p.addLine(to: CGPoint(x: w * 0.78, y: neckY))
            }
            ctx.stroke(cord, with: .color(stringColor), lineWidth: stringWidth)

            // Deux petits brins qui pendent du nœud central, pour
            // l'identification "ficelle". Court, sec, presque un V.
            let tassels = Path { p in
                let cx = w * 0.50
                p.move(to: CGPoint(x: cx, y: neckY))
                p.addLine(to: CGPoint(x: cx - w * 0.10, y: neckY + h * 0.14))
                p.move(to: CGPoint(x: cx, y: neckY))
                p.addLine(to: CGPoint(x: cx + w * 0.10, y: neckY + h * 0.14))
            }
            ctx.stroke(tassels, with: .color(stringColor), lineWidth: max(0.6, w * 0.06))
        }
        .frame(width: size, height: size)
    }
}

/// Petite pièce d'or — utilise désormais l'asset pixel-art `coin.png` si
/// présent dans le bundle. Sinon, retombe sur un dessin vectoriel
/// (disque doré bordé d'encre + croix discrète) — utile comme garde-fou
/// si l'asset est retiré, l'UI ne se brise pas.
struct CoinIcon: View {
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let img = Self.coinImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                vectorFallback
            }
        }
    }

    /// Cache lazy : `coin.png` chargé une fois depuis le bundle. nil si
    /// l'asset est absent (on retombe alors sur le dessin vectoriel).
    private static let coinImage: UIImage? = {
        guard let url = Bundle.main.url(forResource: "coin", withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()

    private var vectorFallback: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.oldGold,
                            Theme.oldGold.opacity(0.65)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size
                    )
                )
            Circle()
                .stroke(Theme.ink.opacity(0.55), lineWidth: max(0.6, size * 0.06))
            Path { p in
                let inset = size * 0.32
                p.move(to: CGPoint(x: size / 2, y: inset))
                p.addLine(to: CGPoint(x: size / 2, y: size - inset))
                p.move(to: CGPoint(x: inset, y: size / 2))
                p.addLine(to: CGPoint(x: size - inset, y: size / 2))
            }
            .stroke(Theme.ink.opacity(0.55), lineWidth: max(0.5, size * 0.06))
        }
        .frame(width: size, height: size)
    }
}

struct InventoryRow: View {
    let itemId: String
    /// True si c'est l'arme actuellement portée. Affiche un petit chip
    /// « Équipée » à la place du bouton.
    var isEquipped: Bool = false
    /// Si non-nil, affiche un chip explicatif à la place du bouton Utiliser
    /// (ex. « Endurance déjà au maximum »). Indique qu'un consommable
    /// existe mais qu'il serait gâché ici.
    var useDisabledReason: String? = nil
    /// Closure « Utiliser » pour les consommables. Nil = item non
    /// consommable OU à effet nul dans l'état courant.
    var onUse: (() -> Void)? = nil
    /// Closure « Équiper » pour les armes non encore portées. Nil = item
    /// non équipable OU déjà équipé.
    var onEquip: (() -> Void)? = nil
    /// Closure « Déséquiper » — pertinente uniquement sur l'arme actuelle.
    /// Utile surtout pour la lame maudite (perte de Chance) qu'on peut
    /// décider de remiser pour récupérer sa stat.
    var onUnequip: (() -> Void)? = nil

    private var info: ItemCatalog.Info { ItemCatalog.info(itemId) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            itemIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(info.name)
                        .font(Theme.display(13))
                        .foregroundColor(Theme.ink)
                    if isEquipped { equippedChip }
                    Spacer(minLength: 0)
                }
                Text(info.description)
                    .font(Theme.body(14))
                    .italic()
                    .foregroundColor(Theme.inkFaded)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let effect = info.effect {
                    Text(effect)
                        .font(Theme.display(10))
                        .foregroundColor(Theme.oldGold)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.oldGold.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Theme.oldGold.opacity(0.35), lineWidth: 0.5)
                        )
                }
                if onUse != nil || onEquip != nil || onUnequip != nil
                    || useDisabledReason != nil || info.bonusAppliedAtPickup {
                    HStack(spacing: 8) {
                        if let onUse {
                            actionButton(label: "Utiliser",
                                         icon: "drop.fill",
                                         tint: Theme.blood,
                                         action: onUse)
                        } else if let reason = useDisabledReason {
                            disabledChip(label: reason, icon: "drop.fill")
                        } else if info.bonusAppliedAtPickup {
                            disabledChip(label: "Effet appliqué",
                                         icon: "checkmark.seal.fill")
                        }
                        if let onEquip {
                            actionButton(label: "Équiper",
                                         icon: "wear",
                                         tint: Theme.inkBlue,
                                         action: onEquip)
                        }
                        if let onUnequip {
                            actionButton(label: "Déséquiper",
                                         icon: "hand.raised.slash.fill",
                                         tint: Theme.inkFaded,
                                         action: onUnequip)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(0.35), lineWidth: 0.6)
        )
        // Items dont l'effet a été appliqué au pickup (bénédictions, sang
        // spectral…) sont légèrement atténués pour signaler qu'ils sont
        // déjà "joués" — ils restent dans le sac comme trace du parcours.
        .opacity(info.bonusAppliedAtPickup ? 0.78 : 1.0)
    }

    private var equippedChip: some View {
        Text("Équipée")
            .font(Theme.display(9))
            .foregroundColor(Theme.parchmentLight)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.inkBlue.opacity(0.85))
            )
    }

    private func actionButton(label: String,
                              icon: String,
                              tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Theme.icon(icon, size: 11, color: Theme.parchmentLight)
                Text(label)
                    .font(Theme.display(11))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(InventoryActionButtonStyle(tint: tint))
    }

    /// Pavé inerte affiché à la place du bouton « Utiliser » quand l'effet
    /// serait gâché (PV ou Chance déjà au max). Visuellement distinct du
    /// bouton : pas de teinte vive, texte gris, pas de tap area.
    private func disabledChip(label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Theme.icon(icon, size: 11, color: Theme.inkFaded.opacity(0.7))
            Text(label)
                .font(Theme.display(11))
        }
        .foregroundColor(Theme.inkFaded.opacity(0.7))
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.40))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Theme.inkFaded.opacity(0.25), lineWidth: 0.5)
        )
    }

    /// Icône d'item : vraie illustration (photo de musée domaine public)
    /// si elle existe dans le bundle, sinon SF Symbol du catalogue.
    /// La photo est désaturée et teintée parchemin pour s'intégrer.
    @ViewBuilder
    private var itemIcon: some View {
        if let image = Self.loadItemImage(itemId: itemId) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipped()
                .saturation(0)
                .colorMultiply(Theme.parchmentLight)
                .overlay(
                    LinearGradient(
                        colors: [.clear, Theme.parchment.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Theme.inkFaded.opacity(0.4), lineWidth: 0.5)
                )
        } else {
            Theme.icon(info.icon, size: 16, color: Theme.oldGold)
                .frame(width: 24, height: 24)
        }
    }

    private static func loadItemImage(itemId: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "item_\(itemId)",
                                         withExtension: "jpg"),
              let img = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return img
    }
}

#Preview {
    ContentView()
}
