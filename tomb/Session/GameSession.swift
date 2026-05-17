//
//  GameSession.swift
//  Wraps `InkStory`: loads adventure.ink, accumulates text and choices,
//  intercepts tags to trigger combat / passive effects, exposes a mutable
//  `PlayerState` and an optional in-progress combat.
//
//  Dependency: `InkSwift` (https://github.com/maartene/InkSwift) added via
//  Swift Package Manager.
//

import Foundation
import SwiftUI
import Combine
import InkSwift

@MainActor
final class GameSession: ObservableObject {

    // MARK: - Observable state

    @Published var player: PlayerState
    @Published var currentText: String = ""
    @Published var currentChoices: [Choice] = []
    @Published var lastMessages: [EventMessage] = []
    @Published var pendingBattle: BattleState? = nil {
        didSet {
            // Filet de sécurité audio : dès que `pendingBattle` retombe à
            // nil (résolution, retour menu, nouvelle partie, save effacée…),
            // on s'assure que la musique de combat s'arrête. `exitBattle()`
            // est idempotent côté AmbientAudio (guard sur `isInBattle`).
            if pendingBattle == nil && oldValue != nil {
                AmbientAudio.shared.exitBattle()
            }
        }
    }
    @Published var isEnded: Bool = false
    @Published var didFailToLoad: Bool = false
    /// false while we're on the menu screen; true once the player has
    /// confirmed their character and entered the adventure.
    @Published var hasStarted: Bool = false
    /// True while the character creation screen is showing.
    @Published var isCreatingCharacter: Bool = false
    /// The current rolled character draft (animated dice + breakdown shown
    /// in the creation screen). Nil while we're not in creation.
    @Published var characterRoll: CharacterRoll? = nil

    // MARK: - Run statistics

    @Published var battlesWon: Int = 0
    @Published var battlesFled: Int = 0
    /// Chapitre narratif actuel — driven by Ink tags (`# chapter: <id>`).
    @Published var currentChapter: Chapter = .village
    /// Issue de la partie. Set par le tag `# outcome: <id>` dans les knots
    /// de fin. Nil tant que l'aventure n'est pas terminée.
    @Published var finalOutcome: FinalOutcome? = nil
    /// Difficulté sélectionnée à la création — affecte le tirage des stats,
    /// les ennemis, et le multiplicateur de score.
    @Published var difficulty: Difficulty = .adventurer
    /// Central burst card shown for major effects (item gain, permanent
    /// bonus). Auto-dismisses after ~1.5s.
    @Published var effectBurst: EffectBurst? = nil
    private var burstTask: Task<Void, Never>? = nil

    /// Overlay des jets de Chance narratifs (pièges, livre maudit, etc.).
    /// Auto-dismiss après ~3.5s.
    @Published var pendingNarrativeLuck: NarrativeLuckRoll? = nil
    private var narrativeLuckTask: Task<Void, Never>? = nil

    /// Demande de jet de Chance qui attend que le joueur clique sur
    /// "Tenter ma chance". `advance()` se met en pause à la rencontre du
    /// premier tag de chance dans un knot, et le bouton apparaît à la
    /// place des choix. Au clic, `triggerLuckRoll()` reprend `advance()`
    /// qui réalise le jet et continue la lecture.
    @Published var pendingLuckPrompt: LuckPromptKind? = nil

    /// Illustration "pleine page" à la mode des livres dont vous êtes le
    /// héros : déclenchée par un tag `# illustration: <name>` dans l'ink,
    /// dont l'image est cherchée dans le bundle sous `illustration_<name>.jpg`.
    /// Le texte et les choix sont masqués tant qu'elle est affichée — le
    /// joueur tape "Continuer" pour la fermer et révéler le passage.
    @Published var pendingIllustration: String? = nil
    /// True le temps d'une reprise post-clic : `advance()` saute alors la
    /// vérification "première rencontre" pour exécuter le tag normalement.
    private var luckPromptResolved: Bool = false
    /// Texte/messages accumulés AVANT la pause, restaurés à la reprise pour
    /// que le passage déjà lu reste affiché pendant le jet.
    private var pausedAccumulated: String? = nil
    private var pausedMessages: [EventMessage]? = nil

    // MARK: - Internals

    /// `var` instead of `let`: we replace the whole instance on each restart
    /// (InkSwift declares `const story` JS-side, so we can't reload the same
    /// story inside the same JavaScriptCore context).
    private var story = InkStory()

    /// Trailing marker placed in adventure.ink on conditional / notable
    /// choices. Stripped before display and surfaced as `Choice.isSpecial`.
    private static let specialMarker = " ★"
    /// Knot to jump to on victory for the in-progress combat.
    private var pendingBattleVictoryPath: String? = nil

    // MARK: - Init

    init() {
        player = PlayerState.rolled()
        // No auto-load. MenuView decides via resume() or startNewGame().
    }

    /// Does a saved game exist in UserDefaults?
    var hasSavedGame: Bool {
        UserDefaults.standard.data(forKey: Self.saveKey) != nil
    }

    /// Supprime la sauvegarde persistée. Appelé depuis l'écran réglages.
    /// Force un objectWillChange pour que `hasSavedGame` soit ré-évalué par
    /// les vues qui en dépendent (le menu, notamment).
    func deleteSave() {
        objectWillChange.send()
        clearSavedState()
    }

    /// Resume the saved game if any; otherwise jump to character creation.
    func resume() {
        if !restoreFromSave() {
            startCharacterCreation()
            return
        }
        hasStarted = true
    }

    /// Enters the character creation screen. Les dés sont désormais tirés un
    /// par un par la `CharacterCreationView` (endurance → habileté → chance),
    /// donc on entre vierge sans pré-tirage.
    func startCharacterCreation() {
        characterRoll = nil
        isCreatingCharacter = true
        hasStarted = false
    }

    /// Reçoit le tirage assemblé par la création de personnage une fois que
    /// les trois dés ont été lancés. Le `PlayerState` est mis à jour pour que
    /// le HUD reflète immédiatement les nouvelles stats.
    func setCharacterRoll(skillDie: Int, staminaDice: (Int, Int), luckDie: Int) {
        let roll = CharacterRoll(
            skillDie: skillDie,
            staminaDice: staminaDice,
            luckDie: luckDie,
            difficulty: difficulty
        )
        characterRoll = roll
        player = roll.player
    }

    /// Changes the difficulty during character creation. Les dés déjà tirés
    /// restent figés : seule la pénalité de difficulté se réapplique sur les
    /// totaux. Plus de re-roll automatique (le joueur doit redémarrer une
    /// partie pour relancer ses dés).
    func setDifficulty(_ d: Difficulty) {
        difficulty = d
        if isCreatingCharacter, let existing = characterRoll {
            let roll = CharacterRoll(
                skillDie: existing.skillDie,
                staminaDice: existing.staminaDice,
                luckDie: existing.luckDie,
                difficulty: d
            )
            characterRoll = roll
            player = roll.player
        }
    }

    /// Cancels character creation and returns to the menu.
    func cancelCharacterCreation() {
        isCreatingCharacter = false
        characterRoll = nil
    }

    /// Confirms the rolled character and starts the adventure.
    func confirmCharacterAndStart() {
        guard let roll = characterRoll else {
            startNewGameDirectly()
            return
        }
        player = roll.player
        isCreatingCharacter = false
        characterRoll = nil
        startNewGameDirectly()
    }

    /// Internal: start a fresh adventure without going through creation.
    /// Used by confirmCharacterAndStart and by restart (end-of-game button).
    private func startNewGameDirectly() {
        clearSavedState()
        currentText = ""
        currentChoices = []
        lastMessages = []
        pendingBattle = nil
        pendingBattleVictoryPath = nil
        // États transitoires qui pourraient survivre d'une partie précédente
        // (mort pendant un jet de chance, illustration encore à l'écran…).
        // On nettoie tout pour repartir vierge.
        pendingIllustration = nil
        pendingLuckPrompt = nil
        pendingNarrativeLuck = nil
        effectBurst = nil
        pausedAccumulated = nil
        pausedMessages = nil
        luckPromptResolved = false
        isEnded = false
        didFailToLoad = false
        battlesWon = 0
        battlesFled = 0
        currentChapter = .village
        finalOutcome = nil
        // Fresh JS context (see also restart()).
        story = InkStory()
        loadStory()
        hasStarted = true
    }

    /// "Recommencer l'aventure" from the ending screen: re-roll a new
    /// character and dive straight into the adventure (no creation screen).
    private func startNewGameWithFreshRoll() {
        player = PlayerState.rolled()
        startNewGameDirectly()
    }

    /// Load the Ink source into `story`. On return, the story is on the
    /// first chunk of the intro.
    private func loadInkSource() -> Bool {
        guard let source = readAdventureSource() else {
            didFailToLoad = true
            currentText = """
            Impossible de charger adventure.ink.

            Vérifie que le fichier est bien ajouté au target dans Xcode
            (Project → Target → Build Phases → Copy Bundle Resources).
            """
            return false
        }
        do {
            try story.loadStory(ink: source)
            return true
        } catch {
            didFailToLoad = true
            // L'erreur Swift seule est generic ("operation couldn't be
            // completed"). On combine :
            //   - le `String(describing:)` qui expose le case enum JXKit
            //     avec son payload (souvent le message JS exact)
            //   - `story.currentErrors` que InkSwift remplit avec les
            //     diagnostics InkJS lors du compile (lignes / colonnes /
            //     symboles attendus)
            let rawError = String(describing: error)
            let inkErrors = story.currentErrors.joined(separator: "\n")
            let detail = inkErrors.isEmpty ? rawError : "\(rawError)\n\nInk:\n\(inkErrors)"
            print("[adventure.ink] load failed:\n\(detail)")
            currentText = """
            Erreur de chargement d'adventure.ink :

            \(detail)
            """
            return false
        }
    }

    /// Reads the Ink source. In Debug, mirrors the bundle file into the app's
    /// Documents directory so the developer can edit the file in place and
    /// reload via "Nouvelle partie" (no rebuild required). The mirror is
    /// refreshed whenever the bundle file is newer than the Documents copy —
    /// typically the case right after a Xcode rebuild — so en code-side
    /// changes ne se font pas masquer par l'ancienne copie persistée.
    /// In Release, reads from the bundle directly.
    private func readAdventureSource() -> String? {
        #if DEBUG
        if let docs = FileManager.default.urls(for: .documentDirectory,
                                                in: .userDomainMask).first,
           let bundleURL = Bundle.main.url(forResource: "adventure",
                                            withExtension: "ink") {
            let editableURL = docs.appendingPathComponent("adventure.ink")
            let fm = FileManager.default

            let docsExists = fm.fileExists(atPath: editableURL.path)
            let bundleMtime = (try? fm.attributesOfItem(atPath: bundleURL.path)[.modificationDate]) as? Date
            let docsMtime = (try? fm.attributesOfItem(atPath: editableURL.path)[.modificationDate]) as? Date

            let needsRefresh: Bool = {
                if !docsExists { return true }
                if let b = bundleMtime, let d = docsMtime { return b > d }
                return false
            }()

            if needsRefresh {
                try? fm.removeItem(at: editableURL)
                try? fm.copyItem(at: bundleURL, to: editableURL)
                print("[adventure.ink] hot-reload copy refreshed (bundle newer) at:\n\(editableURL.path)")
            } else {
                print("[adventure.ink] hot-reload from:\n\(editableURL.path)")
            }

            if let source = try? String(contentsOf: editableURL, encoding: .utf8) {
                return source
            }
        }
        #endif
        guard let url = Bundle.main.url(forResource: "adventure",
                                         withExtension: "ink"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return source
    }

    /// Start from scratch (intro).
    private func loadStory() {
        guard loadInkSource() else { return }
        advance()
    }

    // MARK: - Public API

    func choose(_ choice: Choice) {
        story.chooseChoiceIndex(choice.id, afterChoiceAction: nil)
        advance()
    }

    /// Appelé par le bouton "Continuer" de la planche illustrée pleine page.
    /// Efface l'illustration et révèle le texte + les choix accumulés
    /// pendant `advance()`.
    func dismissIllustration() {
        withAnimation(.easeInOut(duration: 0.35)) {
            pendingIllustration = nil
        }
    }

    /// Appelé par le bouton "Tenter ma chance" : reprend `advance()` qui
    /// va re-rencontrer le tag de chance et exécuter le jet sur cette
    /// itération (parce que `luckPromptResolved` est true).
    func triggerLuckRoll() {
        guard pendingLuckPrompt != nil else { return }
        pendingLuckPrompt = nil
        luckPromptResolved = true
        AmbientAudio.shared.play(.diceRoll)
        advance()
        luckPromptResolved = false
    }

    private func detectLuckPrompt(in tags: [String: String]) -> LuckPromptKind? {
        if tags["luck_test"] != nil { return .generic }
        if tags["luck_test_book"] != nil { return .book }
        if tags["luck_grab_amulette"] != nil { return .amulette }
        return nil
    }

    func resolveBattle(_ outcome: BattleOutcome) {
        let victoryPath = pendingBattleVictoryPath
        pendingBattle = nil
        pendingBattleVictoryPath = nil
        AmbientAudio.shared.exitBattle()

        switch outcome {
        case .victory:
            battlesWon += 1
            if let path = victoryPath {
                story.moveToKnitStitch(path, stitch: nil)
            }
            advance()

        case .defeat:
            story.moveToKnitStitch("death", stitch: nil)
            advance()

        case .fled(let target):
            battlesFled += 1
            story.moveToKnitStitch(target, stitch: nil)
            advance()
        }
    }

    /// Restart the adventure from the intro while staying inside the game
    /// (triggered from the end-of-adventure "Recommencer l'aventure" button).
    /// Re-rolls a fresh character directly (no creation screen).
    func restart() {
        startNewGameWithFreshRoll()
    }

    /// Return to the main menu without touching the save.
    func backToMenu() {
        hasStarted = false
        isCreatingCharacter = false
        characterRoll = nil
    }

    // MARK: - View bindings

    var playerBinding: Binding<PlayerState> {
        Binding(get: { self.player }, set: { self.player = $0 })
    }

    var battleBinding: Binding<BattleState> {
        Binding(
            get: { self.pendingBattle ?? BattleState(setup: BattleSetup(
                enemy: Enemy(id: "?", name: "?", skill: 1, stamina: 1))) },
            set: { self.pendingBattle = $0 }
        )
    }

    // MARK: - Story progression

    /// Accumulates text and effects until we hit a stop (combat, choice, or
    /// end of story).
    ///
    /// Subtlety: InkSwift calls `continueStory()` AUTOMATICALLY at the end of
    /// `loadStory`, `chooseChoiceIndex` and `moveToKnitStitch`. So when we
    /// enter `advance()`, `story.currentText` already holds the first chunk
    /// of the new knot. We read it BEFORE looping.
    private func advance() {
        // Reprise après pause "Tenter ma chance" : on récupère le texte et
        // les messages déjà accumulés avant le clic, pour que le passage
        // reste affiché pendant que les dés roulent.
        var accumulated = pausedAccumulated ?? ""
        var messages: [EventMessage] = pausedMessages ?? []
        pausedAccumulated = nil
        pausedMessages = nil

        // Sync les VARs Ink lues par les conditions de choix.
        // `gold` permet aux choix payants de se masquer si solde insuffisant.
        story.setVariable("gold", to: player.gold)

        while true {
            let chunk = story.currentText
            let tags = story.currentTags

            // ----- 1. Combat: suspend and wait for resolveBattle
            if let enemyId = tags["combat"], let base = EnemyCatalog.all[enemyId] {
                let (enemy, bonusMessage) = applyEnemyModifiers(base, enemyId: enemyId)
                pendingBattleVictoryPath = tags["victory_path"]
                pendingBattle = BattleState(setup: BattleSetup(
                    enemy: enemy,
                    fleeTarget: tags["flee_to"]
                ))
                // Planche pleine page du monstre, façon Tellor : le joueur la
                // ferme avec "Continuer" et la `BattleView` apparaît derrière.
                // L'overlay illustration est au-dessus du combat dans le ZStack
                // de ContentView, donc l'image masque la carte tant qu'elle
                // n'est pas dismissée.
                pendingIllustration = enemyId
                currentText = accumulated
                if let bonusMessage { messages.append(bonusMessage) }
                lastMessages = messages
                currentChoices = []
                AmbientAudio.shared.enterBattle()
                return
            }

            // ----- 1bis. Luck prompt: pause to ask the player to "tenter sa
            // chance" via an explicit button. Skipped on resume (after click)
            // — `luckPromptResolved` is true and we fall through to the tag
            // handler which actually rolls.
            if !luckPromptResolved, let kind = detectLuckPrompt(in: tags) {
                accumulated = appendChunkOnto(accumulated, chunk: chunk)
                currentText = accumulated
                lastMessages = messages
                pausedAccumulated = accumulated
                pausedMessages = messages
                pendingLuckPrompt = kind
                currentChoices = []
                return
            }

            // ----- 2. Passive effects (damage, add_item, luck_*)
            let jumped = applyEffectTags(tags, messages: &messages)
            accumulated = appendChunkOnto(accumulated, chunk: chunk)

            // applyEffectTags may have called moveToKnitStitch("death"),
            // which calls continueStory() internally — story.currentText
            // now reflects the destination knot. Loop again to read it.
            if jumped { continue }

            // 3. Step forward, or break on a choice / END.
            if story.canContinue {
                story.continueStory()
            } else {
                break
            }
        }

        currentText = accumulated
        currentChoices = story.options.map { opt in
            // InkSwift 2.0 doesn't expose per-choice tags. Conditional /
            // notable choices are marked in the .ink with a trailing `★`
            // which we strip here and surface as `isSpecial`.
            let raw = opt.text
            if raw.hasSuffix(Self.specialMarker) {
                let clean = String(raw.dropLast(Self.specialMarker.count))
                    .trimmingCharacters(in: .whitespaces)
                return Choice(id: opt.index, text: clean, isSpecial: true)
            }
            return Choice(id: opt.index, text: raw, isSpecial: false)
        }
        lastMessages = messages
        isEnded = !story.canContinue && story.options.isEmpty

        if isEnded {
            clearSavedState()
        } else {
            saveCurrentState()
        }
    }

    /// Some items grant passive bonuses against specific enemies. Returns
    /// the modified enemy and an optional margin message describing the
    /// bonuses applied.
    private func applyEnemyModifiers(_ enemy: Enemy,
                                      enemyId: String) -> (Enemy, EventMessage?) {
        var modified = enemy

        // Bonus de difficulté (mode Légende).
        modified.skill += difficulty.enemySkillBonus

        var sources: [String] = []
        // Mortimer base + phases multi-combat (phase1/phase2) partagent les
        // mêmes affaiblissements liés aux objets cumulés en chemin.
        if enemyId.hasPrefix("mortimer_spectre") {
            if player.items.contains("protective_charm") {
                modified.skill -= 1
                sources.append("charme du sage")
            }
            if player.items.contains("dead_lord_talisman") {
                modified.skill -= 1
                sources.append("talisman du seigneur")
            }
            if player.items.contains("spirit_blood") {
                modified.skill -= 1
                sources.append("sang spectral")
            }
            if player.items.contains("holy_water") {
                modified.skill -= 1
                sources.append("eau bénite")
            }
        }

        // Le miroir terni gêne le basilic — son regard ne supporte pas son
        // propre reflet.
        if enemyId == "tomb_basilisk" && player.items.contains("tarnished_mirror") {
            modified.skill -= 2
            sources.append("miroir terni")
        }

        guard !sources.isEmpty else { return (modified, nil) }
        let originalWithDifficulty = enemy.skill + difficulty.enemySkillBonus
        let delta = originalWithDifficulty - modified.skill
        let targetLabel = enemyId == "tomb_basilisk" ? "le basilic" : "le spectre"
        let message = EventMessage(
            text: "Tes protections affaiblissent \(targetLabel) : −\(delta) Habileté (\(sources.joined(separator: ", "))).",
            kind: .lucky
        )
        return (modified, message)
    }

    private func appendChunkOnto(_ accumulated: String, chunk: String) -> String {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return accumulated }
        if accumulated.isEmpty { return trimmed }
        return accumulated + "\n\n" + trimmed
    }

    // MARK: - Effect tag application

    /// Process non-combat tags. Returns true if we jumped to `mort` (in which
    /// case the `advance` loop should keep iterating to emit the epitaph).
    private func applyEffectTags(_ tags: [String: String],
                                  messages: inout [EventMessage]) -> Bool {
        // chapter: <id> — switch the displayed chapter heading.
        if let raw = tags["chapter"], let chap = Chapter(rawValue: raw) {
            currentChapter = chap
        }

        // illustration: <name> — affiche une planche pleine page que le
        // joueur ferme en tapant "Continuer". L'image attendue est
        // `illustration_<name>.jpg` dans le bundle.
        if let name = tags["illustration"] {
            pendingIllustration = name
        }

        // outcome: <id> — final outcome of the adventure (for the ending screen).
        if let raw = tags["outcome"], let outcome = FinalOutcome(rawValue: raw) {
            finalOutcome = outcome
        }

        // add_item: <id>
        if let item = tags["add_item"] {
            player.items.insert(item)
            story.setVariable("has_\(item)", to: 1)
            messages.append(EventMessage(
                text: "Tu obtiens : \(itemDisplayName(item)).",
                kind: .gain
            ))
            AmbientAudio.shared.play(.gainItem)
            showBurst(EffectBurst(
                icon: "sparkles",
                title: "Tu obtiens",
                subtitle: itemDisplayName(item),
                tint: Theme.oldGold
            ))
        }

        // damage: <n>
        if let dmgString = tags["damage"], let dmg = Int(dmgString) {
            player.stamina -= dmg
            messages.append(EventMessage(
                text: "Tu perds \(dmg) Endurance.",
                kind: .damage
            ))
            AmbientAudio.shared.play(.takeHit)
            if player.stamina <= 0 {
                story.moveToKnitStitch("death", stitch: nil)
                return true
            }
        }

        // heal: <n>
        if let healString = tags["heal"], let heal = Int(healString) {
            player.stamina = min(player.stamina + heal, player.staminaMax)
            messages.append(EventMessage(
                text: "Tu récupères \(heal) Endurance.",
                kind: .heal
            ))
            AmbientAudio.shared.play(.heal)
        }

        // spend_gold: <n>
        if let goldString = tags["spend_gold"], let n = Int(goldString) {
            player.gold = max(0, player.gold - n)
            // Resync de la VAR Ink dans le même advance() : si d'autres choix
            // payants se présentent plus loin dans la même séquence, ils
            // doivent voir le nouveau solde.
            story.setVariable("gold", to: player.gold)
            messages.append(EventMessage(
                text: "Tu dépenses \(n) pièce\(n > 1 ? "s" : "") d'or.",
                kind: .loss
            ))
        }

        // gain_gold: <n> — récompense narrative en pièces.
        if let goldString = tags["gain_gold"], let n = Int(goldString) {
            player.gold += n
            story.setVariable("gold", to: player.gold)
            messages.append(EventMessage(
                text: "Tu ramasses \(n) pièce\(n > 1 ? "s" : "") d'or.",
                kind: .gain
            ))
        }

        // skill_bonus: <n> — permanent +n to Skill and SkillMax.
        if let s = tags["skill_bonus"], let n = Int(s) {
            player.skill += n
            player.skillMax += n
            messages.append(EventMessage(
                text: "Ton Habileté progresse de \(n) point\(n > 1 ? "s" : "").",
                kind: .gain
            ))
            AmbientAudio.shared.play(.lucky)
            showBurst(EffectBurst(
                icon: "burst.fill",
                title: "Habileté +\(n)",
                subtitle: "Bonus permanent",
                tint: Theme.inkBlue
            ))
        }

        // stamina_bonus: <n> — permanent +n to Stamina max.
        // L'endurance courante monte d'autant pour ne pas faire ressentir
        // l'augmentation comme un soin manqué.
        if let s = tags["stamina_bonus"], let n = Int(s) {
            player.staminaMax += n
            player.stamina += n
            messages.append(EventMessage(
                text: "Ton Endurance maximale progresse de \(n) point\(n > 1 ? "s" : "").",
                kind: .gain
            ))
            AmbientAudio.shared.play(.lucky)
            showBurst(EffectBurst(
                icon: "heart.fill",
                title: "Endurance +\(n)",
                subtitle: "Maximum élevé",
                tint: Theme.blood
            ))
        }

        // luck_bonus: <n> — permanent +n to Luck and LuckMax.
        if let s = tags["luck_bonus"], let n = Int(s) {
            player.luck += n
            player.luckMax += n
            messages.append(EventMessage(
                text: "Ta Chance progresse de \(n) point\(n > 1 ? "s" : "").",
                kind: .gain
            ))
            AmbientAudio.shared.play(.lucky)
            showBurst(EffectBurst(
                icon: "sparkles",
                title: "Chance +\(n)",
                subtitle: "Bonus permanent",
                tint: Theme.verdigris
            ))
        }

        // luck_restore: Luck reset to its maximum.
        if tags["luck_restore"] != nil {
            player.luck = player.luckMax
            messages.append(EventMessage(
                text: "Ta Chance est restaurée (\(player.luckMax)).",
                kind: .lucky
            ))
            AmbientAudio.shared.play(.lucky)
        }

        // luck_test_book: lucky → luck restored to max; unlucky → -4 stamina.
        if tags["luck_test_book"] != nil {
            let d = (Int.random(in: 1...6), Int.random(in: 1...6))
            let (lucky, roll, threshold) = player.testLuck(roll: d.0 + d.1)
            showNarrativeLuck(dice: d, threshold: threshold, lucky: lucky)
            if lucky {
                player.luck = player.luckMax
                messages.append(EventMessage(
                    text: "Chanceux (\(roll) ≤ \(threshold)). Un sort se grave dans ta mémoire et restaure ta Chance.",
                    kind: .lucky
                ))
                AmbientAudio.shared.play(.lucky)
            } else {
                player.stamina -= 4
                messages.append(EventMessage(
                    text: "Malchanceux (\(roll) > \(threshold)). Les mots t'écorchent l'esprit : −4 Endurance.",
                    kind: .unlucky
                ))
                AmbientAudio.shared.play(.unlucky)
                if player.stamina <= 0 {
                    story.moveToKnitStitch("death", stitch: nil)
                    return true
                }
            }
        }

        // luck_test: -4 stamina on failure. Message générique : le contexte
        // (ex. "les lames jaillissent") est donné par le passage lui-même.
        if tags["luck_test"] != nil {
            let d = (Int.random(in: 1...6), Int.random(in: 1...6))
            let (lucky, roll, threshold) = player.testLuck(roll: d.0 + d.1)
            showNarrativeLuck(dice: d, threshold: threshold, lucky: lucky)
            if lucky {
                messages.append(EventMessage(
                    text: "Chanceux (\(roll) ≤ \(threshold)). Tu t'en sors indemne.",
                    kind: .lucky
                ))
                AmbientAudio.shared.play(.lucky)
            } else {
                player.stamina -= 4
                messages.append(EventMessage(
                    text: "Malchanceux (\(roll) > \(threshold)). Tu perds 4 points d'Endurance.",
                    kind: .unlucky
                ))
                AmbientAudio.shared.play(.unlucky)
                if player.stamina <= 0 {
                    story.moveToKnitStitch("death", stitch: nil)
                    return true
                }
            }
        }

        // luck_grab_amulette: Mortimer special-case.
        if tags["luck_grab_amulette"] != nil {
            let d = (Int.random(in: 1...6), Int.random(in: 1...6))
            let (lucky, roll, threshold) = player.testLuck(roll: d.0 + d.1)
            showNarrativeLuck(dice: d, threshold: threshold, lucky: lucky)
            if lucky {
                player.items.insert("amulet")
                story.setVariable("has_amulet", to: 1)
                messages.append(EventMessage(
                    text: "Chanceux (\(roll) ≤ \(threshold)) ! Tu saisis l'amulette et fonces vers la sortie.",
                    kind: .lucky
                ))
                AmbientAudio.shared.play(.gainItem)
            } else {
                messages.append(EventMessage(
                    text: "Malchanceux (\(roll) > \(threshold)). Le spectre te happe avant la porte.",
                    kind: .unlucky
                ))
                player.stamina = 0
                story.moveToKnitStitch("death", stitch: nil)
                return true
            }
        }

        // ending: victory | defeat — final jingle
        if let ending = tags["ending"] {
            switch ending {
            case "victory": AmbientAudio.shared.play(.victory)
            case "defeat":  AmbientAudio.shared.play(.death)
            default: break
            }
        }

        return false
    }

    // MARK: - Save / load

    /// Bumpé à v9 avec la deuxième vague d'expansion (Roncebrune élargi,
    /// forêt profonde, aile sud du tombeau) : la place du village, le
    /// carrefour et le couloir gagnent encore plus de choix, et de nouvelles
    /// `VAR has_*` apparaissent. Les saves v8 auraient des indices de choix
    /// qui ne correspondent plus.
    private static let saveKey = "tomb.save.v11"

    private struct SaveData: Codable {
        let player: PlayerState
        let storyState: String          // story.stateToJSON()
        let currentText: String
        let currentChoices: [Choice]
        let lastMessages: [EventMessage]
        let battlesWon: Int
        let battlesFled: Int
        let currentChapter: Chapter
        let difficulty: Difficulty
    }

    /// Serialises the current narrative state into UserDefaults. Only called
    /// on stable states (not in combat, not isEnded).
    private func saveCurrentState() {
        let save = SaveData(
            player: player,
            storyState: story.stateToJSON(),
            currentText: currentText,
            currentChoices: currentChoices,
            lastMessages: lastMessages,
            battlesWon: battlesWon,
            battlesFled: battlesFled,
            currentChapter: currentChapter,
            difficulty: difficulty
        )
        if let data = try? JSONEncoder().encode(save) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
        }
    }

    /// Try to restore an existing save. Returns true on success.
    private func restoreFromSave() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey) else {
            return false
        }
        guard let save = try? JSONDecoder().decode(SaveData.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.saveKey)
            return false
        }

        // 1. Fresh JS context — without this, reloading on the same InkStory
        //    throws "Identifier 'story' has already been declared", which used
        //    to silently send the player back to character creation.
        story = InkStory()
        // 2. Reload the Ink source (otherwise story.loadState has nothing to hydrate).
        guard loadInkSource() else { return false }
        // 3. Restore the Ink pointer. loadState calls continueStory() internally,
        //    but we overwrite currentText with the saved snapshot anyway: the
        //    effect tags won't be replayed.
        story.loadState(save.storyState)

        player = save.player
        currentText = save.currentText
        currentChoices = save.currentChoices
        lastMessages = save.lastMessages
        battlesWon = save.battlesWon
        battlesFled = save.battlesFled
        currentChapter = save.currentChapter
        difficulty = save.difficulty
        isEnded = false
        pendingBattle = nil
        return true
    }

    private func clearSavedState() {
        UserDefaults.standard.removeObject(forKey: Self.saveKey)
    }

    // MARK: - Display

    private func itemDisplayName(_ id: String) -> String {
        ItemCatalog.info(id).name
    }

    // MARK: - Effect burst

    private func showBurst(_ burst: EffectBurst) {
        burstTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            effectBurst = burst
        }
        burstTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.3)) {
                effectBurst = nil
            }
        }
    }

    private func showNarrativeLuck(dice: (Int, Int), threshold: Int, lucky: Bool) {
        narrativeLuckTask?.cancel()
        let roll = NarrativeLuckRoll(dice: dice, threshold: threshold, lucky: lucky)
        withAnimation(.easeOut(duration: 0.3)) {
            pendingNarrativeLuck = roll
        }
        narrativeLuckTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(3500))
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.3)) {
                pendingNarrativeLuck = nil
            }
        }
    }

    // MARK: - Score & grade

    /// Score final de l'aventure : combats, exploration, état du héros, fin
    /// choisie. Calculé à la volée à partir du PlayerState et des stats.
    var finalScore: Int {
        var score = 0
        score += battlesWon * 50
        score -= battlesFled * 20

        let staminaRatio = player.staminaMax > 0
            ? Double(max(player.stamina, 0)) / Double(player.staminaMax)
            : 0
        let luckRatio = player.luckMax > 0
            ? Double(max(player.luck, 0)) / Double(player.luckMax)
            : 0
        score += Int(staminaRatio * 100)
        score += Int(luckRatio * 60)

        score += player.items.count * 30
        score += player.gold * 5

        switch finalOutcome {
        case .honour:        score += 200
        case .destruction:   score += 300
        case .transcendence: score += 500
        case .dark:          score -= 200
        case .death:         score -= 100
        case .none:          break
        }

        if player.items.contains("silver_chain") {
            score += 100
        }

        let finalRaw = Double(max(0, score)) * difficulty.scoreMultiplier
        return Int(finalRaw.rounded())
    }

    /// Titre thématique correspondant au score / outcome.
    var gradeTitle: String {
        switch finalOutcome {
        case .dark:  return "Le Voleur de Roncebrune"
        case .death: return "Le Tombeau t'a englouti"
        default: break
        }
        switch finalScore {
        case 0..<250:     return "Voyageur Perdu"
        case 250..<500:   return "Aventurier Survivant"
        case 500..<800:   return "Héros de Roncebrune"
        case 800..<1100:  return "Maître du Tombeau"
        default:          return "Légende du Tombeau"
        }
    }
}
