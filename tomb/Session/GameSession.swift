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
            if pendingBattle == nil && oldValue != nil {
                AmbientAudio.shared.exitBattle()
            }
        }
    }
    @Published var isEnded: Bool = false
    @Published var didFailToLoad: Bool = false
    @Published var hasStarted: Bool = false
    @Published var isCreatingCharacter: Bool = false
    @Published var characterRoll: CharacterRoll? = nil

    // MARK: - Run statistics

    @Published var battlesWon: Int = 0
    @Published var runStartedAt: Date? = nil
    @Published var quickWinsThisRun: Int = 0
    @Published var completedRuns: Int = 0
    @Published var battlesFled: Int = 0
    @Published var currentChapter: Chapter = .village
    @Published var pendingChapterTransition: Chapter? = nil
    @Published var finalOutcome: FinalOutcome? = nil
    @Published var deathCinematicActive: Bool = false
    @Published var unseenItems: Set<String> = []
    @Published var difficulty: Difficulty = .adventurer
    @Published var effectBurst: EffectBurst? = nil

    @Published var pendingNarrativeLuck: NarrativeLuckRoll? = nil
    private var narrativeLuckTask: Task<Void, Never>? = nil

    @Published var pendingLuckPrompt: LuckPromptKind? = nil

    @Published var pendingIllustration: String? = nil
    private var luckPromptResolved: Bool = false
    private var pausedAccumulated: String? = nil
    private var pausedMessages: [EventMessage]? = nil

    // MARK: - Internals

    private var story = InkStory()

    private static let specialMarker = " ★"

    private static let goldPriceRegex = #/\s*\(\$(\d+)\)\s*$/#

    private static func parseChoice(rawText: String, index: Int) -> Choice {
        var text = rawText
        var price: Int? = nil

        if let match = text.firstMatch(of: goldPriceRegex) {
            price = Int(match.output.1)
            text.removeSubrange(match.range)
        }

        var isSpecial = false
        if text.hasSuffix(specialMarker) {
            text = String(text.dropLast(specialMarker.count))
            isSpecial = true
        }

        text = text.trimmingCharacters(in: .whitespaces)
        return Choice(id: index, text: text,
                      isSpecial: isSpecial, priceGold: price)
    }
    private var pendingBattleVictoryPath: String? = nil

    @Published var discoveredEndings: Set<FinalOutcome> = []

    @Published var defeatedEnemies: Set<String> = []

    @Published var unlockedAchievements: Set<String> = []

    @Published var potionsUsedThisRun: Int = 0

    @Published var inventoryPulse: Int = 0

    // MARK: - Init

    init() {
        player = PlayerState.rolled()
        discoveredEndings = Self.loadDiscoveredEndings()
        defeatedEnemies = Self.loadDefeatedEnemies()
        unlockedAchievements = Self.loadAchievements()
        completedRuns = Self.loadCompletedRuns()
    }

    var hasSavedGame: Bool {
        UserDefaults.standard.data(forKey: Self.saveKey) != nil
    }

    func deleteSave() {
        objectWillChange.send()
        clearSavedState()
    }

    func resume() {
        if !restoreFromSave() {
            startCharacterCreation()
            return
        }
        hasStarted = true
    }

    func startCharacterCreation() {
        characterRoll = nil
        isCreatingCharacter = true
        hasStarted = false
    }

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

    func cancelCharacterCreation() {
        isCreatingCharacter = false
        characterRoll = nil
    }

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

    private func startNewGameDirectly() {
        clearSavedState()
        currentText = ""
        currentChoices = []
        lastMessages = []
        pendingBattle = nil
        pendingBattleVictoryPath = nil
        resetTransientEffects()
        isEnded = false
        didFailToLoad = false
        battlesWon = 0
        battlesFled = 0
        potionsUsedThisRun = 0
        quickWinsThisRun = 0
        currentChapter = .village
        finalOutcome = nil
        runStartedAt = Date()
        unseenItems = []
        story = InkStory()
        loadStory()
        hasStarted = true
    }

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
            let rawError = String(describing: error)
            let inkErrors = story.currentErrors.joined(separator: "\n")
            let detail = inkErrors.isEmpty ? rawError : "\(rawError)\n\nInk:\n\(inkErrors)"
            #if DEBUG
            print("[adventure.ink] load failed:\n\(detail)")
            #endif
            currentText = """
            Erreur de chargement d'adventure.ink :

            \(detail)
            """
            return false
        }
    }

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

    private func loadStory() {
        guard loadInkSource() else { return }
        advance()
    }

    // MARK: - Public API

    func choose(_ choice: Choice) {
        story.chooseChoiceIndex(choice.id, afterChoiceAction: nil)
        advance()
    }

    func dismissIllustration() {
        withAnimation(.easeInOut(duration: 0.35)) {
            pendingIllustration = nil
        }
    }

    func triggerLuckRoll() {
        guard pendingLuckPrompt != nil else { return }
        pendingLuckPrompt = nil
        AmbientAudio.shared.play(.diceRoll)
        // ⚠️ Différer `advance()` au prochain runloop. Sans ça, l'appel
        // synchrone enchaîne InkSwift (JavaScriptCore) + `showNarrativeLuck`
        // + `deferLuckTestStatChange` + plusieurs `withAnimation` + state
        // mutations, et bloque le main thread ~100–200 ms. Symptômes :
        //   - le buffer audio du dice_roll grésille (CPU étouffé)
        //   - UIKit lève « System gesture gate timed out » parce que la
        //     phase de release du tap n'a pas pu être finalisée
        // En déférant, le tap se termine proprement et SwiftUI re-render
        // (bouton qui disparaît) avant qu'`advance()` ne reprenne la main.
        DispatchQueue.main.async { [self] in
            luckPromptResolved = true
            advance()
            luckPromptResolved = false
        }
    }

    private func detectLuckPrompt(in tags: [String: String]) -> LuckPromptKind? {
        if tags["luck_test"] != nil { return .generic }
        if tags["luck_test_book"] != nil { return .book }
        if tags["luck_grab_amulette"] != nil { return .amulette }
        return nil
    }

    func resolveBattle(_ outcome: BattleOutcome) {
        let victoryPath = pendingBattleVictoryPath
        let enemyId = pendingBattle?.enemy.id
        let roundCount = pendingBattle?.roundCount ?? 0
        pendingBattle = nil
        pendingBattleVictoryPath = nil
        AmbientAudio.shared.exitBattle()

        switch outcome {
        case .victory:
            battlesWon += 1
            if roundCount > 0 && roundCount < 6 {
                quickWinsThisRun += 1
            }
            if let enemyId { recordDefeatedEnemy(enemyId) }
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

    func restart() {
        AmbientAudio.shared.exitBattle()
        pendingBattle = nil
        pendingBattleVictoryPath = nil
        resetTransientEffects()
        finalOutcome = nil
        isEnded = false
        hasStarted = false
        startCharacterCreation()
    }

    func backToMenu() {
        hasStarted = false
        isCreatingCharacter = false
        characterRoll = nil
        AmbientAudio.shared.exitBattle()
        pendingBattle = nil
        resetTransientEffects()
        if finalOutcome != nil || isEnded {
            clearSavedState()
            objectWillChange.send()
        }
    }

    // MARK: - Items consommables & équipement

    func useItem(_ itemId: String) {
        guard let info = ItemCatalog.all[itemId],
              let effect = info.consumable else { return }
        guard player.items.contains(itemId) else { return }
        guard !isEnded else { return }
        if let battle = pendingBattle, battle.phase != .awaitingAction {
            return
        }
        guard isUseful(effect: effect) else { return }

        var msg: EventMessage
        switch effect {
        case .heal(let n):
            let before = player.stamina
            player.stamina = min(player.stamina + n, player.staminaMax)
            let gained = player.stamina - before
            msg = EventMessage(
                text: "Tu utilises : \(info.name). +\(gained) Endurance.",
                kind: .heal
            )
            AmbientAudio.shared.play(.heal)
        case .restoreLuck:
            player.luck = player.luckMax
            msg = EventMessage(
                text: "Tu utilises : \(info.name). Chance ramenée au maximum.",
                kind: .lucky
            )
            AmbientAudio.shared.play(.lucky)
        case .boostSkillNextAttack(let n):
            pendingBattle?.playerSkillBonus += n
            pendingBattle?.log.append(BattleLogEntry(
                text: "Tu utilises : \(info.name). +\(n) Habileté au prochain coup.",
                kind: .info
            ))
            msg = EventMessage(
                text: "Tu utilises : \(info.name). +\(n) Habileté au prochain coup.",
                kind: .info
            )
            AmbientAudio.shared.play(.lucky)
        case .weakenEnemyNextAttack(let n):
            pendingBattle?.enemySkillPenalty += n
            let enemyName = pendingBattle?.enemy.name ?? "L'ennemi"
            pendingBattle?.log.append(BattleLogEntry(
                text: "Tu utilises : \(info.name). \(enemyName) perd \(n) Habileté pour le prochain round.",
                kind: .lucky
            ))
            msg = EventMessage(
                text: "Tu utilises : \(info.name). \(enemyName) perd \(n) Habileté.",
                kind: .lucky
            )
            AmbientAudio.shared.play(.lucky)
        }

        player.items.remove(itemId)
        story.setVariable("has_\(itemId)", to: 0)
        if case .heal = effect { potionsUsedThisRun += 1 }
        if case .restoreLuck = effect { potionsUsedThisRun += 1 }
        lastMessages = [msg]
        saveCurrentState()
        checkAchievements()
    }

    func isUseful(effect: ConsumableEffect) -> Bool {
        switch effect {
        case .boostSkillNextAttack, .weakenEnemyNextAttack:
            return pendingBattle != nil
        case .heal:
            return player.stamina < player.staminaMax
        case .restoreLuck:
            return player.luck < player.luckMax
        }
    }

    func equipWeapon(_ itemId: String) {
        guard let info = ItemCatalog.all[itemId],
              let weapon = info.weapon,
              player.items.contains(itemId) else { return }
        if player.equippedWeapon == itemId { return }

        unequipWeapon(silent: true)

        guard player.canEquip(weapon) else {
            lastMessages = [EventMessage(
                text: "Tu n'es pas en état de porter \(info.name) — il te faudrait plus de ressources.",
                kind: .info
            )]
            return
        }

        applyWeaponBonus(weapon, sign: +1)
        player.equippedWeapon = itemId
        lastMessages = [EventMessage(
            text: "Tu portes maintenant : \(info.name).",
            kind: .info
        )]
        saveCurrentState()
    }

    func unequipWeapon(silent: Bool = false) {
        guard let id = player.equippedWeapon,
              let info = ItemCatalog.all[id],
              let weapon = info.weapon else { return }
        applyWeaponBonus(weapon, sign: -1)
        player.equippedWeapon = nil
        if !silent {
            lastMessages = [EventMessage(
                text: "Tu ranges : \(info.name).",
                kind: .info
            )]
        }
        saveCurrentState()
    }

    private func applyWeaponBonus(_ weapon: WeaponKind, sign: Int) {
        player.applyWeaponBonus(weapon, sign: sign)
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

    private func advance() {
        var accumulated = pausedAccumulated ?? ""
        var messages: [EventMessage] = pausedMessages ?? []
        pausedAccumulated = nil
        pausedMessages = nil

        story.setVariable("gold", to: player.gold)

        while true {
            let chunk = story.currentText
            let tags = story.currentTags

            if let enemyId = tags["combat"], let base = EnemyCatalog.all[enemyId] {
                // ⚠️ La musique de combat doit démarrer le plus tôt
                // possible. On appelle enterBattle() AVANT les state
                // updates SwiftUI : ainsi l'engine audio commence la
                // lecture pendant que SwiftUI prépare le re-render de
                // l'illustration. Différence perceptible ~50-100 ms.
                AmbientAudio.shared.enterBattle()

                let (enemy, bonusMessage) = applyEnemyModifiers(base, enemyId: enemyId)
                pendingBattleVictoryPath = tags["victory_path"]
                pendingBattle = BattleState(setup: BattleSetup(
                    enemy: enemy,
                    fleeTarget: tags["flee_to"]
                ))
                pendingIllustration = enemyId
                currentText = accumulated
                if let bonusMessage { messages.append(bonusMessage) }
                lastMessages = messages
                currentChoices = []
                return
            }

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

            let jumped = applyEffectTags(tags, messages: &messages)
            accumulated = appendChunkOnto(accumulated, chunk: chunk)

            if jumped { continue }

            if story.canContinue {
                story.continueStory()
            } else {
                break
            }
        }

        currentText = accumulated
        currentChoices = story.options.map { opt in
            return Self.parseChoice(rawText: opt.text, index: opt.index)
        }
        lastMessages = messages
        isEnded = !story.canContinue && story.options.isEmpty

        if isEnded || finalOutcome != nil {
            clearSavedState()
        } else {
            saveCurrentState()
        }
        checkAchievements()
    }

    private func applyEnemyModifiers(_ enemy: Enemy,
                                      enemyId: String) -> (Enemy, EventMessage?) {
        var modified = enemy

        modified.skill += difficulty.enemySkillBonus

        var sources: [String] = []
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

    private func applyEffectTags(_ tags: [String: String],
                                  messages: inout [EventMessage]) -> Bool {
        if let raw = tags["chapter"], let chap = Chapter(rawValue: raw) {
            let previous = currentChapter
            currentChapter = chap
            if chap != previous {
                pendingChapterTransition = chap
                AmbientAudio.shared.setChapterAmbience(chap)
            }
        }

        if let name = tags["illustration"] {
            pendingIllustration = name
        }

        // outcome: <id> — final outcome of the adventure (for the ending screen).
        //
        // ⚠️ On clear la sauvegarde DÈS QU'UN OUTCOME EST POSÉ (death,
        // honour, destruction, dark, transcendence). Sans ça, si le joueur
        // mourait puis revenait au menu et cliquait « Reprendre », il
        // restaurait l'état sauvegardé juste avant la mort et pouvait
        // recommencer le combat à l'infini — bypass de la mort permanente.
        // Le `clearSavedState()` de fin d'`advance()` (sur isEnded)
        // suffisait quand le knot final terminait proprement, mais ce
        // n'est pas garanti dans tous les cas — on sécurise ici.
        if let raw = tags["outcome"], let outcome = FinalOutcome(rawValue: raw) {
            finalOutcome = outcome
            recordDiscoveredEnding(outcome)
            clearSavedState()
            // Cinématique de mort : on déclenche le voile rouge → noir +
            // épitaphe avant que l'écran de fin n'apparaisse, pour marquer
            // dramatiquement le moment. Les autres fins (honour, dark…)
            // restent en révélation directe — ce sont des moments de
            // triomphe ou de mystère, pas de violence subie.
            //
            // ⚠️ Le knot `death` du .ink pose à la fois `# chapter: ending`
            // et `# outcome: death`. Sans ce reset, on voyait pendant ~4 s
            // l'overlay « Épilogue » (chapitre) ET la cinématique d'épitaphe
            // s'empiler sur deux z-index différents. La mort prime : on
            // efface la transition de chapitre.
            if outcome == .death {
                pendingChapterTransition = nil
                deathCinematicActive = true
            } else {
                recordCompletedRun()
            }
        }

        if let raw = tags["add_item"] {
            let items = raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for item in items {
                let alreadyOwned = player.items.contains(item)
                player.items.insert(item)
                story.setVariable("has_\(item)", to: 1)
                guard !alreadyOwned else { continue }
                unseenItems.insert(item)
                messages.append(EventMessage(
                    text: "Tu obtiens : \(itemDisplayName(item)).",
                    kind: .gain,
                    iconOverride: "get_items"
                ))
                AmbientAudio.shared.play(.gainItem)
                showBurst(EffectBurst(
                    icon: "get_items",
                    title: "Tu obtiens",
                    subtitle: itemDisplayName(item),
                    tint: Theme.oldGold
                ))
                if let info = ItemCatalog.all[item],
                   let weapon = info.weapon,
                   player.equippedWeapon == nil {
                    applyWeaponBonus(weapon, sign: +1)
                    player.equippedWeapon = item
                }
                if ItemCatalog.all[item]?.consumable != nil {
                    inventoryPulse += 1
                }
            }
        }

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

        if let healString = tags["heal"], let heal = Int(healString) {
            player.stamina = min(player.stamina + heal, player.staminaMax)
            messages.append(EventMessage(
                text: "Tu récupères \(heal) Endurance.",
                kind: .heal
            ))
            AmbientAudio.shared.play(.heal)
        }

        if let goldString = tags["spend_gold"], let n = Int(goldString) {
            player.gold = max(0, player.gold - n)
            story.setVariable("gold", to: player.gold)
            messages.append(EventMessage(
                text: "Tu dépenses \(n) pièce\(n > 1 ? "s" : "") d'or.",
                kind: .loss,
                iconOverride: "coin"
            ))
        }

        if let goldString = tags["gain_gold"], let n = Int(goldString) {
            player.gold += n
            story.setVariable("gold", to: player.gold)
            messages.append(EventMessage(
                text: "Tu ramasses \(n) pièce\(n > 1 ? "s" : "") d'or.",
                kind: .gain
            ))
        }

        // skill_bonus: <n> — permanent +n to Skill and SkillMax.
        //
        // ⚠️ Cohérence UI : les bonus permanents de stats (skill/stamina/
        // luck) ne déclenchent PLUS de popin `EffectBurst` — uniquement
        // une `MarginNote` dans le journal. Avant, certains events stats
        // popinaient et d'autres non (damage / heal restaient simples
        // bandeaux), créant une inconsistance ressentie comme du bruit.
        // Les popins sont désormais réservées aux `add_item` (gain d'objet
        // = vrai « moment de récompense » distinct des variations chiffrées).
        if let s = tags["skill_bonus"], let n = Int(s) {
            player.skill += n
            player.skillMax += n
            messages.append(EventMessage(
                text: "Ton Habileté progresse de \(n) point\(n > 1 ? "s" : "").",
                kind: .gain
            ))
            AmbientAudio.shared.play(.lucky)
        }

        if let s = tags["stamina_bonus"], let n = Int(s) {
            player.staminaMax += n
            player.stamina += n
            messages.append(EventMessage(
                text: "Ton Endurance maximale progresse de \(n) point\(n > 1 ? "s" : "").",
                kind: .gain,
                iconOverride: "gain_life"
            ))
            AmbientAudio.shared.play(.lucky)
        }

        if let s = tags["luck_bonus"], let n = Int(s) {
            player.luck += n
            player.luckMax += n
            if n > 0 {
                messages.append(EventMessage(
                    text: "Ta Chance progresse de \(n) point\(n > 1 ? "s" : "").",
                    kind: .gain,
                    iconOverride: "gain_luck"
                ))
                AmbientAudio.shared.play(.lucky)
            } else if n < 0 {
                let lost = abs(n)
                messages.append(EventMessage(
                    text: "Quelque chose en toi s'éteint un peu. Ta Chance recule de \(lost) point\(lost > 1 ? "s" : "").",
                    kind: .unlucky
                ))
                AmbientAudio.shared.play(.unlucky)
            }
        }

        if tags["luck_restore"] != nil {
            player.luck = player.luckMax
            messages.append(EventMessage(
                text: "Ta Chance est restaurée (\(player.luckMax)).",
                kind: .lucky,
                iconOverride: "gain_luck"
            ))
            AmbientAudio.shared.play(.lucky)
        }

        // luck_test_book: lucky → luck restored to max; unlucky → -4 stamina.
        //
        // ⚠️ Les mutations de stats (`player.luck`, `player.stamina`) sont
        // toutes différées jusqu'à la fin de l'animation des dés (~1.9 s)
        // pour que le joueur voie d'abord rouler les dés, puis voie le
        // chiffre baisser dans son HUD — synchronisé visuellement. Sinon
        // la jauge baissait avant même que les dés n'aient quitté la main.
        if tags["luck_test_book"] != nil {
            let d = (Int.random(in: 1...6), Int.random(in: 1...6))
            let roll = d.0 + d.1
            let threshold = player.luck
            let lucky = roll <= threshold
            showNarrativeLuck(dice: d, threshold: threshold, lucky: lucky)
            if lucky {
                messages.append(EventMessage(
                    text: "Chanceux (\(roll) ≤ \(threshold)). Un sort se grave dans ta mémoire et restaure ta Chance.",
                    kind: .lucky,
                    iconOverride: "luck_up"
                ))
                AmbientAudio.shared.play(.lucky)
                deferLuckTestStatChange {
                    self.player.luck = self.player.luckMax
                }
            } else {
                messages.append(EventMessage(
                    text: "Malchanceux (\(roll) > \(threshold)). Les mots t'écorchent l'esprit : −4 Endurance.",
                    kind: .unlucky
                ))
                AmbientAudio.shared.play(.unlucky)
                deferLuckTestStatChange {
                    self.player.luck -= 1
                    self.player.stamina -= 4
                    if self.player.stamina <= 0 {
                        self.story.moveToKnitStitch("death", stitch: nil)
                        self.advance()
                    }
                }
            }
        }

        if tags["luck_test"] != nil {
            let d = (Int.random(in: 1...6), Int.random(in: 1...6))
            let roll = d.0 + d.1
            let threshold = player.luck
            let lucky = roll <= threshold
            showNarrativeLuck(dice: d, threshold: threshold, lucky: lucky)
            if lucky {
                messages.append(EventMessage(
                    text: "Chanceux (\(roll) ≤ \(threshold)). Tu t'en sors indemne.",
                    kind: .lucky
                ))
                AmbientAudio.shared.play(.lucky)
                deferLuckTestStatChange {
                    self.player.luck -= 1
                }
            } else {
                messages.append(EventMessage(
                    text: "Malchanceux (\(roll) > \(threshold)). Tu perds 4 points d'Endurance.",
                    kind: .unlucky
                ))
                AmbientAudio.shared.play(.unlucky)
                deferLuckTestStatChange {
                    self.player.luck -= 1
                    self.player.stamina -= 4
                    if self.player.stamina <= 0 {
                        self.story.moveToKnitStitch("death", stitch: nil)
                        self.advance()
                    }
                }
            }
        }

        if tags["luck_grab_amulette"] != nil {
            let d = (Int.random(in: 1...6), Int.random(in: 1...6))
            let roll = d.0 + d.1
            let threshold = player.luck
            let lucky = roll <= threshold
            showNarrativeLuck(dice: d, threshold: threshold, lucky: lucky)
            if lucky {
                messages.append(EventMessage(
                    text: "Chanceux (\(roll) ≤ \(threshold)) ! Tu saisis l'amulette et fonces vers la sortie.",
                    kind: .lucky
                ))
                AmbientAudio.shared.play(.gainItem)
                deferLuckTestStatChange {
                    self.player.luck -= 1
                    self.player.items.insert("amulet")
                    self.story.setVariable("has_amulet", to: 1)
                }
            } else {
                messages.append(EventMessage(
                    text: "Malchanceux (\(roll) > \(threshold)). Le spectre te happe avant la porte.",
                    kind: .unlucky
                ))
                deferLuckTestStatChange {
                    self.player.luck -= 1
                    self.player.stamina = 0
                    self.story.moveToKnitStitch("death", stitch: nil)
                    self.advance()
                }
            }
        }

        if let ending = tags["ending"] {
            switch ending {
            case "victory": AmbientAudio.shared.play(.victory)
            case "defeat":  AmbientAudio.shared.play(.death)
            default: break
            }
        }

        return false
    }

    // MARK: - Méta-progression (persistée hors save de run)

    private static let kDiscoveredEndings = "tomb.meta.endings"
    private static let kDefeatedEnemies   = "tomb.meta.bestiary"
    private static let kAchievements      = "tomb.meta.achievements"
    private static let kCompletedRuns     = "tomb.meta.completed_runs"

    private func recordDiscoveredEnding(_ outcome: FinalOutcome) {
        if discoveredEndings.insert(outcome).inserted {
            Self.persistDiscoveredEndings(discoveredEndings)
        }
    }

    private func recordDefeatedEnemy(_ enemyId: String) {
        if defeatedEnemies.insert(enemyId).inserted {
            Self.persistDefeatedEnemies(defeatedEnemies)
        }
    }

    private static func loadDiscoveredEndings() -> Set<FinalOutcome> {
        guard let raw = UserDefaults.standard.array(forKey: kDiscoveredEndings) as? [String] else {
            return []
        }
        return Set(raw.compactMap { FinalOutcome(rawValue: $0) })
    }

    private static func persistDiscoveredEndings(_ set: Set<FinalOutcome>) {
        UserDefaults.standard.set(set.map { $0.rawValue }, forKey: kDiscoveredEndings)
    }

    private static func loadDefeatedEnemies() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: kDefeatedEnemies) ?? [])
    }

    private static func persistDefeatedEnemies(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: kDefeatedEnemies)
    }

    private static func loadAchievements() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: kAchievements) ?? [])
    }

    private static func persistAchievements(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: kAchievements)
    }

    private static func loadCompletedRuns() -> Int {
        UserDefaults.standard.integer(forKey: kCompletedRuns)
    }

    private static func persistCompletedRuns(_ count: Int) {
        UserDefaults.standard.set(count, forKey: kCompletedRuns)
    }

    private func recordCompletedRun() {
        completedRuns += 1
        Self.persistCompletedRuns(completedRuns)
    }

    func checkAchievements() {
        var newlyUnlocked: [Achievement] = []
        for ach in AchievementsCatalog.all where !unlockedAchievements.contains(ach.id) {
            if achievementSatisfied(ach.id) {
                unlockedAchievements.insert(ach.id)
                newlyUnlocked.append(ach)
            }
        }
        guard !newlyUnlocked.isEmpty else { return }
        Self.persistAchievements(unlockedAchievements)
        scheduleAchievementBursts(newlyUnlocked)
    }

    private func achievementSatisfied(_ id: String) -> Bool {
        switch id {
        case AchievementsCatalog.ID.firstBlood:
            return battlesWon >= 1

        case AchievementsCatalog.ID.pacifist:
            return finalOutcome == .honour && battlesWon <= 2

        case AchievementsCatalog.ID.ironMan:
            return finalOutcome != nil && finalOutcome != .death && potionsUsedThisRun == 0

        case AchievementsCatalog.ID.collector:
            return player.items.count >= 10

        case AchievementsCatalog.ID.cartographer:
            return discoveredEndings.count >= FinalOutcome.allCases.count

        case AchievementsCatalog.ID.bestiaryFull:
            return EnemyCatalog.bestiaryComplete.isSubset(of: defeatedEnemies)

        case AchievementsCatalog.ID.rich:
            return finalOutcome != nil && finalOutcome != .death && player.gold >= 30

        case AchievementsCatalog.ID.survivor:
            guard finalOutcome == .honour else { return false }
            let ratio = Double(player.stamina) / Double(max(1, player.staminaMax))
            return ratio >= 0.9

        case AchievementsCatalog.ID.legend:
            return finalOutcome != nil && finalOutcome != .death && difficulty == .legend

        case AchievementsCatalog.ID.triadOfHerald:
            return finalOutcome != nil && finalOutcome != .death
                && player.items.contains("protective_charm")
                && player.items.contains("dead_lord_talisman")
                && player.items.contains("spirit_blood")

        case AchievementsCatalog.ID.cursedAndProud:
            return finalOutcome != nil && finalOutcome != .death
                && player.equippedWeapon == "cursed_blade"

        case AchievementsCatalog.ID.widowsPromise:
            return finalOutcome == .honour
                && player.items.contains("silver_chain")

        case AchievementsCatalog.ID.mortimerSeesYou:
            return finalOutcome != nil && finalOutcome != .death
                && player.items.contains("mortimer_attention")

        case AchievementsCatalog.ID.perfectRun:
            return finalOutcome == .transcendence

        case AchievementsCatalog.ID.threeEndings:
            return discoveredEndings.count >= 3

        case AchievementsCatalog.ID.bestiaryHalf:
            return defeatedEnemies.count >= 10

        case AchievementsCatalog.ID.speedrunner:
            guard let start = runStartedAt,
                  finalOutcome != nil,
                  finalOutcome != .death else { return false }
            return Date().timeIntervalSince(start) < 20 * 60

        case AchievementsCatalog.ID.tombeauRevisited:
            return completedRuns >= 3

        case AchievementsCatalog.ID.hecatomb:
            return quickWinsThisRun >= 3

        default:
            return false
        }
    }

    private func scheduleAchievementBursts(_ achievements: [Achievement]) {
        Task { @MainActor in
            for (idx, ach) in achievements.enumerated() {
                if idx > 0 {
                    try? await Task.sleep(for: .milliseconds(2200))
                }
                showBurst(EffectBurst(
                    icon: ach.icon,
                    title: "Haut fait",
                    subtitle: ach.title,
                    tint: Theme.oldGold
                ))
                AmbientAudio.shared.play(.gainItem)
            }
        }
    }

    // MARK: - Save / load

    private static let saveKey = "tomb.save.v12"

    private struct SaveData: Codable {
        let player: PlayerState
        let storyState: String
        let currentText: String
        let currentChoices: [Choice]
        let lastMessages: [EventMessage]
        let battlesWon: Int
        let battlesFled: Int
        let currentChapter: Chapter
        let difficulty: Difficulty
        let potionsUsedThisRun: Int?
        let runStartedAt: Date?
        let quickWinsThisRun: Int?
    }

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
            difficulty: difficulty,
            potionsUsedThisRun: potionsUsedThisRun,
            runStartedAt: runStartedAt,
            quickWinsThisRun: quickWinsThisRun
        )
        if let data = try? JSONEncoder().encode(save) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
        }
    }

    private func restoreFromSave() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey) else {
            return false
        }
        guard let save = try? JSONDecoder().decode(SaveData.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.saveKey)
            return false
        }

        story = InkStory()
        guard loadInkSource() else { return false }
        story.loadState(save.storyState)

        player = save.player
        currentText = save.currentText
        currentChoices = save.currentChoices
        lastMessages = save.lastMessages
        battlesWon = save.battlesWon
        battlesFled = save.battlesFled
        potionsUsedThisRun = save.potionsUsedThisRun ?? 0
        quickWinsThisRun = save.quickWinsThisRun ?? 0
        currentChapter = save.currentChapter
        difficulty = save.difficulty
        runStartedAt = save.runStartedAt
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

    private var burstQueue: [EffectBurst] = []
    private var burstDraining = false
    private var burstTask: Task<Void, Never>? = nil

    private func showBurst(_ burst: EffectBurst) {
        burstQueue.append(burst)
        guard !burstDraining else { return }
        burstDraining = true
        burstTask = Task { @MainActor in
            await drainBurstQueue()
        }
    }

    private func resetTransientEffects() {
        burstTask?.cancel()
        burstTask = nil
        burstQueue.removeAll()
        burstDraining = false
        effectBurst = nil

        narrativeLuckTask?.cancel()
        narrativeLuckTask = nil
        pendingNarrativeLuck = nil

        pendingIllustration = nil
        pendingLuckPrompt = nil
        pausedAccumulated = nil
        pausedMessages = nil
        luckPromptResolved = false

        pendingChapterTransition = nil
        deathCinematicActive = false
    }

    @MainActor
    private func drainBurstQueue() async {
        defer { burstDraining = false }
        while !burstQueue.isEmpty {
            let next = burstQueue.removeFirst()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                effectBurst = next
            }
            try? await Task.sleep(for: .milliseconds(2000))
            withAnimation(.easeOut(duration: 0.30)) {
                effectBurst = nil
            }
            try? await Task.sleep(for: .milliseconds(250))
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

    private func deferLuckTestStatChange(_ change: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1900))
            change()
        }
    }

    // MARK: - Score & grade

    var runDurationText: String? {
        guard let start = runStartedAt else { return nil }
        let elapsed = Int(Date().timeIntervalSince(start))
        guard elapsed > 0 else { return "moins d'une seconde" }
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        if h > 0 {
            return "\(h) h \(String(format: "%02d", m)) min"
        } else if m > 0 {
            return "\(m) min \(String(format: "%02d", s)) s"
        } else {
            return "\(s) s"
        }
    }

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
