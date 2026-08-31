import SwiftUI

struct ContentView: View {
    @StateObject private var session = GameSession()
    @StateObject private var audio = AmbientAudio.shared
    @State private var showingInventory = false
    @State private var showingMenuConfirm = false
    @State private var passageRevealed = false
    @State private var isChoosing = false

    // MARK: - Page-turn orchestration

    @State private var visibleText: String = ""
    @State private var pageRotation: Double = 0
    private let flipHalfMs = 280
    @State private var flipTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleMargins: [EventMessage] {
        guard session.pendingNarrativeLuck != nil else { return session.lastMessages }
        return session.lastMessages.filter { $0.kind != .lucky && $0.kind != .unlucky }
    }

    private var consumableCount: Int {
        session.player.items.reduce(0) { acc, id in
            acc + (ItemCatalog.all[id]?.consumable != nil ? 1 : 0)
        }
    }

    var body: some View {
        ZStack {
            Theme.pageBackground

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

            if let burst = session.effectBurst {
                EffectBurstView(burst: burst)
                    .id(burst.id)
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            if let luckRoll = session.pendingNarrativeLuck {
                NarrativeLuckOverlay(roll: luckRoll)
                    .id(luckRoll.id)
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

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

            if let newChapter = session.pendingChapterTransition {
                ChapterTransitionOverlay(chapter: newChapter) {
                    session.pendingChapterTransition = nil
                }
                .ignoresSafeArea()
                .zIndex(50)
                .transition(.opacity)
            }

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
                                              anchor: .leading,
                                              perspective: 0.6)
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
                                            guard !isChoosing else { return }
                                            isChoosing = true
                                            passageRevealed = false
                                            AmbientAudio.shared.play(.pageTurn)
                                            session.choose(choice)
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
            if revealed { isChoosing = false }
        }
    }

    // MARK: - Page-turn

    private func syncVisibleText() {
        if visibleText != session.currentText {
            visibleText = session.currentText
        }
    }

    private func flipTo(_ newText: String) {
        guard newText != visibleText else { return }
        if visibleText.isEmpty {
            visibleText = newText
            return
        }

        if reduceMotion {
            flipTask?.cancel()
            pageRotation = 0
            withAnimation(.easeInOut(duration: 0.25)) {
                visibleText = newText
            }
            return
        }

        flipTask?.cancel()
        let half = Double(flipHalfMs) / 1000.0

        flipTask = Task { @MainActor in
            withAnimation(.easeIn(duration: half)) {
                pageRotation = 90
            }
            try? await Task.sleep(for: .milliseconds(flipHalfMs))
            if Task.isCancelled { return }

            visibleText = newText
            pageRotation = -90

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

    @ViewBuilder
    private var outcomeHeader: some View {
        if let outcome = session.finalOutcome {
            VStack(spacing: 10) {
                if outcome == .death {
                    Theme.icon("epitaph", size: 40, color: Theme.ink)
                } else {
                    Text("⚜")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.oldGold.opacity(0.7))
                }
                Text(outcome.title)
                    .font(Theme.serif(26, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .multilineTextAlignment(.center)
                    .shadow(color: Theme.oldGold.opacity(0.25), radius: 4, x: 0, y: 1)
                    .lineSpacing(2)
                Rectangle()
                    .fill(Theme.inkFaded.opacity(0.4))
                    .frame(width: 60, height: 0.6)
                Text(outcome.blurb)
                    .font(Theme.serif(14))
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

    private var gradeCard: some View {
        VStack(spacing: 4) {
            Text(session.gradeTitle)
                .font(Theme.serif(18, weight: .bold))
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)
            Text("\(session.finalScore) points")
                .font(Theme.display(12))
                .foregroundColor(Theme.goldInk)
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
                    .font(Theme.serif(16, weight: .semibold))
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
                    .font(Theme.serif(16, weight: .semibold))
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
        .parchmentCard(lineWidth: 0.6)
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
                .font(Theme.serif(16, weight: .semibold))
                .foregroundColor(Theme.ink)
                .monospacedDigit()
        }
    }
}

// MARK: - Note en marge (effet d'un choix : dégâts, objet trouvé, etc.)

struct MarginNote: View {
    let message: EventMessage

    private var icon: String {
        if let override = message.iconOverride { return override }
        switch message.kind {
        case .gain:    return "sparkles"
        case .heal:    return "heal_up"
        case .damage:  return "heal_down"
        case .loss:    return "minus.circle.fill"
        case .lucky:   return "star.fill"
        case .unlucky: return "trap"
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

    private static func loadIllustration(named name: String) -> UIImage? {
        if let img = Theme.photo(named: "illustration_\(name)") { return img }
        if let img = Theme.photo(named: name) { return img }
        if let stripped = Theme.strippingPhaseSuffix(name) {
            return loadIllustration(named: stripped)
        }
        return nil
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

// MARK: - Liste de choix

struct ChoicesList: View {
    let choices: [Choice]
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

struct LuckPromptButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Theme.icon("try_luck", size: 18, color: Theme.oldGold)
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
    let playerGold: Int
    let action: () -> Void

    private var isUnaffordable: Bool {
        if let price = choice.priceGold, price > playerGold { return true }
        return false
    }

    private var choiceIconName: String {
        if isReturn { return "return_option" }
        if isDialogue { return "dialogue_option" }
        return "classic_option"
    }

    private var isDialogue: Bool {
        guard !choice.isSpecial else { return false }
        let trimmed = choice.text.trimmingCharacters(in: .whitespaces).lowercased()
        return Self.dialogueOpeners.contains { trimmed.hasPrefix($0) }
    }

    private static let dialogueOpeners = [
        "saluer", "parler", "demander", "discuter", "interroger",
        "répondre", "lui demander", "lui parler", "lui glisser",
        "le saluer", "la saluer", "lui dire",
        "lui offrir une pièce", "le remercier", "le supplier",
        "murmurer", "écouter"
    ]

    private var isReturn: Bool {
        guard !choice.isSpecial else { return false }
        let trimmed = choice.text.trimmingCharacters(in: .whitespaces).lowercased()
        return Self.returnOpeners.contains { trimmed.hasPrefix($0) }
    }

    private static let returnOpeners = [
        "retour", "revenir", "remonter", "remonte",
        "reprendre la piste", "reprendre les ruelles",
        "repartir", "retourner", "retourne",
        "te ressaisir", "te recueillir",
        "souffler un coup", "redescendre"
    ]

    var body: some View {
        Button(action: { if !isUnaffordable { action() } }) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if choice.isSpecial {
                    Theme.icon("item_option", size: 14, color: Theme.oldGold)
                } else {
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

struct GameHUD: View {
    let player: PlayerState
    let chapter: Chapter?
    let anticipatedDamage: Int
    let showsResourcesAndInventory: Bool
    let isInCombat: Bool
    let consumableCount: Int
    let inventoryPulseTrigger: Int
    let potionsUsed: Int
    let onOpenInventory: () -> Void
    let onReturnToMenu: () -> Void

    @State private var lastStamina: Int = -1
    @State private var staminaFloater: StaminaFloater? = nil
    @State private var hitFlash: Bool = false
    @State private var hitShakeOffset: CGFloat = 0
    @State private var hitParticleTrigger: UUID = UUID()
    @State private var showHitParticles: Bool = false
    @State private var shakeTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var staminaRatio: Double {
        guard player.staminaMax > 0 else { return 0 }
        return Swift.min(1.0, Double(Swift.max(player.stamina, 0)) / Double(player.staminaMax))
    }

    private var dangerStartRatio: Double {
        guard player.staminaMax > 0, anticipatedDamage > 0 else { return staminaRatio }
        let dangerStart = max(0, player.stamina - anticipatedDamage)
        return Double(dangerStart) / Double(player.staminaMax)
    }

    var body: some View {
        VStack(spacing: 4) {
            if chapter != nil || isInCombat {
                HStack(spacing: 8) {
                    if let chapter { chapterChip(chapter) }
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
        .onDisappear {
            shakeTask?.cancel()
            shakeTask = nil
        }
        .onChange(of: player.stamina) { oldValue, newValue in
            guard isInCombat else { return }
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

    private func chapterChip(_ chapter: Chapter) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 5))
                .foregroundColor(Theme.oldGold.opacity(0.7))
            Text(chapter.shortTitle.uppercased())
                .font(Theme.display(10))
                .tracking(1.8)
                .foregroundColor(Theme.goldInk)
            Image(systemName: "diamond.fill")
                .font(.system(size: 5))
                .foregroundColor(Theme.oldGold.opacity(0.7))
        }
    }

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

    private func triggerHit() {
        withAnimation(.easeOut(duration: 0.12)) { hitFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeIn(duration: 0.25)) { hitFlash = false }
        }
        shakeTask?.cancel()
        shakeTask = Task { @MainActor in
            await Shake.play(Shake.steps(intensity: 8),
                             reduceMotion: reduceMotion) { hitShakeOffset = $0 }
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
                .minimumTapTarget()
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

// MARK: - Bouton inventaire avec badge + pulse

struct InventoryHUDButton: View {
    let consumableCount: Int
    let pulseTrigger: Int
    let action: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
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
            .minimumTapTarget()
        }
        .buttonStyle(HudIconButtonStyle(isActive: true))
        .accessibilityLabel(consumableCount > 0
            ? "Ouvrir l'inventaire — \(consumableCount) consommable\(consumableCount > 1 ? "s" : "")"
            : "Ouvrir l'inventaire")
        .onChange(of: pulseTrigger) { _, _ in
            runPulse()
        }
    }

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

#Preview {
    ContentView()
}
