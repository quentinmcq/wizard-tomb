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

    var body: some View {
        ZStack {
            Theme.pageBackground

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
        }
        .animation(.easeInOut(duration: 0.35), value: session.hasStarted)
        .animation(.easeInOut(duration: 0.35), value: session.isCreatingCharacter)
        .animation(.easeIn(duration: 0.35), value: passageRevealed)
        .sheet(isPresented: $showingInventory) {
            InventoryView(player: session.player)
        }
        .confirmationDialog(
            "Quitter l'aventure ?",
            isPresented: $showingMenuConfirm,
            titleVisibility: .visible
        ) {
            Button("Retour au menu") {
                withAnimation(.easeInOut(duration: 0.35)) {
                    session.backToMenu()
                }
            }
            Button("Annuler", role: .cancel) {}
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
                                       onEnd: session.resolveBattle)
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
        VStack(spacing: 8) {
            // Grade card
            VStack(spacing: 4) {
                Text(session.gradeTitle)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("\(session.finalScore) points")
                    .font(Theme.display(12))
                    .foregroundColor(Theme.oldGold)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.oldGold.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.oldGold.opacity(0.55), lineWidth: 0.8)
            )
            .padding(.bottom, 8)

            Text("Récit de ton aventure")
                .font(Theme.display(13))
                .foregroundColor(Theme.inkFaded)
                .padding(.bottom, 4)

            row(icon: "burst.fill",
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

            row(icon: "heart.fill",
                tint: Theme.blood,
                label: "Endurance finale",
                value: "\(max(session.player.stamina, 0)) / \(session.player.staminaMax)")

            row(icon: "sparkles",
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
        case .heal:    return "heart.fill"
        case .damage:  return "burst.fill"
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
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
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
    let onChoose: (Choice) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(choices) { choice in
                ChoiceButton(choice: choice) { onChoose(choice) }
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
                Image(systemName: "die.face.6.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.oldGold)
                Text(label)
                    .font(Theme.display(15))
                    .foregroundColor(Theme.ink)
                Spacer(minLength: 0)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(ChoiceButtonStyle(isSpecial: choice.isSpecial))
    }
}

struct ChoiceButtonStyle: ButtonStyle {
    let isSpecial: Bool

    private var baseFill: Color {
        isSpecial ? Theme.oldGold.opacity(0.14) : Theme.parchmentLight.opacity(0.55)
    }

    private var pressedFill: Color {
        isSpecial ? Theme.oldGold.opacity(0.30) : Theme.parchmentLight.opacity(0.95)
    }

    private var strokeColor: Color {
        isSpecial ? Theme.oldGold.opacity(0.55) : Theme.inkFaded.opacity(0.55)
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
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - HUD des statistiques

struct StatsHUD: View {
    let player: PlayerState
    @ObservedObject var audio: AmbientAudio
    let onOpenInventory: () -> Void
    let onReturnToMenu: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            StatBadge(icon: "burst.fill",
                      value: player.skill, max: player.skillMax,
                      color: Theme.inkBlue,
                      criticalThreshold: nil,
                      accessibility: "Habileté")
            fleuronDivider
            StatBadge(icon: "heart.fill",
                      value: player.stamina, max: player.staminaMax,
                      color: Theme.blood,
                      criticalThreshold: max(1, player.staminaMax / 4),
                      accessibility: "Endurance")
            fleuronDivider
            StatBadge(icon: "sparkles",
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
            Image(systemName: "house.fill")
                .font(.system(size: 13))
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
        Button(action: onOpenInventory) {
            PouchIcon(size: 16, tint: Theme.inkFaded)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HudIconButtonStyle(isActive: true))
        .accessibilityLabel("Ouvrir l'inventaire")
    }

    private var audioToggle: some View {
        // `isPlaying` ne reflète que le drone d'ambiance. On préfère regarder
        // les deux préférences (ambiance + effets) pour que l'icône soit
        // cohérente avec ce que le bouton fait — couper TOUT.
        let anyAudio = audio.ambientEnabled || audio.effectsEnabled
        return Button {
            audio.toggle()
        } label: {
            Image(systemName: anyAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 13))
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
struct CompactBattleHUD: View {
    let player: PlayerState
    let onReturnToMenu: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            StatBadge(icon: "burst.fill",
                      value: player.skill, max: player.skillMax,
                      color: Theme.inkBlue,
                      criticalThreshold: nil,
                      accessibility: "Habileté")
            fleuronDivider
            StatBadge(icon: "heart.fill",
                      value: player.stamina, max: player.staminaMax,
                      color: Theme.blood,
                      criticalThreshold: max(1, player.staminaMax / 4),
                      accessibility: "Endurance")
            fleuronDivider
            StatBadge(icon: "sparkles",
                      value: player.luck, max: player.luckMax,
                      color: Theme.verdigris,
                      criticalThreshold: 3,
                      accessibility: "Chance")
            Spacer(minLength: 4)
            Button(action: onReturnToMenu) {
                Image(systemName: "house.fill")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HudIconButtonStyle(isActive: true))
            .accessibilityLabel("Retour au menu principal")
        }
        .ornamentedHudFrame()
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

// MARK: - ButtonStyle pour les boutons du HUD

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
    let player: PlayerState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground
                ScrollView {
                    VStack(spacing: 16) {
                        ResourceCard(gold: player.gold)
                        if player.items.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(Array(player.items).sorted(), id: \.self) { itemId in
                                    InventoryRow(itemId: itemId)
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
            Image(systemName: "bag")
                .font(.system(size: 28))
                .foregroundColor(Theme.inkFaded.opacity(0.6))
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

/// Petite pièce d'or stylisée : disque doré bordé d'encre, traversé d'une
/// croix discrète façon piécette frappée d'un sceau. Utilisée dans le HUD
/// et dans l'inventaire pour rester cohérent — c'est le seul SF Symbol
/// "coin" qui ne tombe pas dans le moderne (dollar, bitcoin).
struct CoinIcon: View {
    var size: CGFloat = 14

    var body: some View {
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
            // Petite croix d'encre au centre, façon piécette frappée.
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

    private var info: ItemCatalog.Info { ItemCatalog.info(itemId) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            itemIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(info.name)
                    .font(Theme.display(13))
                    .foregroundColor(Theme.ink)
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
            Image(systemName: info.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.oldGold)
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
