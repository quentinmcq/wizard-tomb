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
    /// Horodatage du début de la run en cours. Set par
    /// `startNewGameDirectly()`, conservé dans la sauvegarde et restauré à
    /// la reprise. Nil tant qu'aucune partie n'a été démarrée — affiché à
    /// la fin (« Temps de jeu : 47 min 12 s »). On accepte le biais
    /// « player quits then resumes 3 days later » : pour ce jeu, c'est
    /// précis à 1-2 sessions près et raconte mieux l'aventure que de
    /// finasser sur le pause/reprise.
    @Published var runStartedAt: Date? = nil
    /// Nombre de combats remportés en moins de 6 rounds dans la run en
    /// cours. Atteint 3 → succès « Hécatombe ». Reset au démarrage d'une
    /// nouvelle aventure.
    @Published var quickWinsThisRun: Int = 0
    /// Compteur cumulatif de runs complétées (victoire ou défaite finale
    /// autre que `death`). Persisté en UserDefaults. Cf. succès « Tombeau
    /// revisité » (3+).
    @Published var completedRuns: Int = 0
    @Published var battlesFled: Int = 0
    /// Chapitre narratif actuel — driven by Ink tags (`# chapter: <id>`).
    @Published var currentChapter: Chapter = .village
    /// Transition cinématique en cours : fixé brièvement (~2.5 s) quand
    /// le joueur franchit un nouveau chapitre, pour que la vue affiche
    /// un overlay « Chapitre III — Le marais » par-dessus la narration.
    /// Reset à nil par la vue après l'animation.
    @Published var pendingChapterTransition: Chapter? = nil
    /// Issue de la partie. Set par le tag `# outcome: <id>` dans les knots
    /// de fin. Nil tant que l'aventure n'est pas terminée.
    @Published var finalOutcome: FinalOutcome? = nil
    /// Cinématique de mort en cours. Posé à `true` au moment où l'outcome
    /// `.death` est résolu, et reset à `false` par la vue après l'animation
    /// d'épitaphe (~3 s). Permet de différer l'apparition de l'écran de fin
    /// pour donner un poids dramatique à la mort.
    @Published var deathCinematicActive: Bool = false
    /// Items ramassés que le joueur n'a pas encore consultés dans l'écran
    /// d'inventaire — affichés avec un pip doré « nouveau » dans la liste.
    /// Pas persisté en save (état de session) : à la reprise, tous les
    /// items sont considérés comme déjà vus, ce qui est cohérent avec le
    /// fait que l'utilisateur les a probablement vus avant de quitter.
    @Published var unseenItems: Set<String> = []
    /// Difficulté sélectionnée à la création — affecte le tirage des stats,
    /// les ennemis, et le multiplicateur de score.
    @Published var difficulty: Difficulty = .adventurer
    /// Central burst card shown for major effects (item gain, permanent
    /// bonus). Auto-dismisses after ~1.5s.
    @Published var effectBurst: EffectBurst? = nil
    // (Anciennement `burstTask` — remplacé par `burstQueue` + `drainBurstQueue`
    // pour gérer plusieurs effets enchaînés dans un même tour.)

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

    /// Regex pour le marker de coût en or `($5)` en fin de texte de choix.
    /// Les parenthèses sont préférées aux crochets parce que Ink utilise
    /// déjà `[...]` pour délimiter le texte de choix — des crochets nichés
    /// font planter le parser. Capture le nombre, qu'on remonte ensuite
    /// dans `Choice.priceGold`.
    private static let goldPriceRegex = #/\s*\(\$(\d+)\)\s*$/#

    /// Parse un texte de choix Ink brut : extrait les markers `★` (special)
    /// et `($N)` (coût en or), nettoie le texte affiché, renvoie le `Choice`.
    /// Centralisé ici pour éviter de répéter la logique dans `advance()`.
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
    /// Knot to jump to on victory for the in-progress combat.
    private var pendingBattleVictoryPath: String? = nil

    /// Fins déjà atteintes par le joueur (persistées entre les parties).
    /// Permet d'afficher l'écran « Tes aventures » avec les fins découvertes
    /// vs encore mystérieuses.
    @Published var discoveredEndings: Set<FinalOutcome> = []

    /// Ennemis déjà vaincus (persistés). Alimente le bestiaire.
    @Published var defeatedEnemies: Set<String> = []

    /// Hauts faits débloqués (persistés). Alimente l'écran AchievementsView
    /// et déclenche des bursts à chaque déblocage.
    @Published var unlockedAchievements: Set<String> = []

    /// Compteur de potions/herbes consommées sur la partie en cours. Sert
    /// au haut fait « Iron-man ». Reset à zéro sur new game.
    @Published var potionsUsedThisRun: Int = 0

    /// Compteur incrémenté à chaque pickup d'un item consommable. Le HUD
    /// observe le changement via `.onChange` pour faire pulser le bouton
    /// inventaire — façon « ding, regarde ce que tu viens de ranger ». La
    /// valeur en elle-même n'a pas de sens, seul le delta importe.
    @Published var inventoryPulse: Int = 0

    // MARK: - Init

    init() {
        player = PlayerState.rolled()
        discoveredEndings = Self.loadDiscoveredEndings()
        defeatedEnemies = Self.loadDefeatedEnemies()
        unlockedAchievements = Self.loadAchievements()
        completedRuns = Self.loadCompletedRuns()
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
        potionsUsedThisRun = 0
        quickWinsThisRun = 0
        currentChapter = .village
        finalOutcome = nil
        runStartedAt = Date()
        unseenItems = []
        // Fresh JS context (see also restart()).
        story = InkStory()
        loadStory()
        hasStarted = true
    }

    // `startNewGameWithFreshRoll` retiré : « Recommencer l'aventure »
    // passe désormais par `startCharacterCreation()` (cf. `restart()`)
    // pour que le joueur retrouve le rituel des jets de dés. L'ancienne
    // version skippait la création, ce qui privait le ré-jeu de son
    // moment d'identification au héros.

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
        // Cache le bouton tout de suite : retour UI instantané, le joueur
        // sent que son tap a été pris en compte.
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
        // Capturer le compteur de rounds AVANT de relâcher pendingBattle :
        // sert au succès « Hécatombe » (3 victoires en <6 rounds dans une
        // même run).
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

    /// Restart the adventure from the intro while staying inside the game
    /// (triggered from the end-of-adventure "Recommencer l'aventure" button).
    /// Passe par la phase de jets de dés — re-rouler les stats fait partie
    /// du rituel Fighting Fantasy et l'ancien comportement (« skip creation
    /// screen ») privait le joueur de ce moment.
    func restart() {
        // On clear l'état de la run précédente avant d'entrer en création :
        // ennemi en attente, illustration, états transitoires…
        AmbientAudio.shared.exitBattle()
        pendingBattle = nil
        pendingBattleVictoryPath = nil
        pendingIllustration = nil
        pendingLuckPrompt = nil
        pendingNarrativeLuck = nil
        effectBurst = nil
        pausedAccumulated = nil
        pausedMessages = nil
        luckPromptResolved = false
        finalOutcome = nil
        isEnded = false
        hasStarted = false
        startCharacterCreation()
    }

    /// Return to the main menu. Touche normalement pas à la sauvegarde
    /// (pour qu'une partie en cours soit reprenable depuis le menu) —
    /// sauf si la partie s'est terminée (`finalOutcome != nil`) : dans
    /// ce cas, on efface la sauvegarde par sécurité pour que le menu
    /// affiche « Commencer la partie » et non « Reprendre » + écran de
    /// fin.
    func backToMenu() {
        hasStarted = false
        isCreatingCharacter = false
        characterRoll = nil
        // Si on quitte en plein milieu d'un combat, la musique de combat
        // continuait tourner sur le menu d'accueil. `exitBattle()` est
        // idempotent (guard sur `isInBattle`) — safe à appeler dans tous
        // les cas. Crossfade ambient ↔ combat se résout proprement.
        AmbientAudio.shared.exitBattle()
        // Reset aussi l'état combat côté session pour que le HUD ne
        // re-rentre pas en mode combat si le joueur reprend la partie.
        pendingBattle = nil
        pendingIllustration = nil
        if finalOutcome != nil || isEnded {
            clearSavedState()
            objectWillChange.send()
        }
    }

    // MARK: - Items consommables & équipement

    /// Utilise un item du sac (potion, herbes…). L'effet est appliqué et
    /// l'item disparaît de l'inventaire. Le `has_<id>` côté Ink est repassé
    /// à 0 pour qu'un choix conditionnel ne propose plus l'item.
    func useItem(_ itemId: String) {
        guard let info = ItemCatalog.all[itemId],
              let effect = info.consumable else { return }
        guard player.items.contains(itemId) else { return }
        guard !isEnded else { return }
        // En combat : seulement pendant `.awaitingAction` (entre les rounds,
        // pas pendant un prompt de Chance). Hors combat : toujours OK.
        if let battle = pendingBattle, battle.phase != .awaitingAction {
            return
        }
        // Pas de gaspillage : on bloque l'usage d'un soin à PV pleins ou
        // d'un restore de Chance à Chance pleine. L'UI gris déjà le bouton,
        // c'est juste un garde-fou en plus.
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
        // Compteur de potions : on ne compte que les soins/restores "vrais"
        // pour l'achievement Iron-man. Les bonus combat à usage unique
        // n'entrent pas dans le décompte.
        if case .heal = effect { potionsUsedThisRun += 1 }
        if case .restoreLuck = effect { potionsUsedThisRun += 1 }
        lastMessages = [msg]
        saveCurrentState()
        checkAchievements()
    }

    /// Vrai si appliquer cet effet va réellement changer l'état du joueur
    /// (par opposition à un soin sur PV pleins ou un restore de Chance déjà
    /// au max — l'objet serait gâché pour rien). Les effets de combat ne
    /// sont "utiles" que si on est effectivement en combat.
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

    /// Équipe une arme. Si une arme est déjà équipée, son bonus est rendu
    /// avant d'appliquer le nouveau. Idempotent si l'item donné est déjà
    /// l'arme courante.
    func equipWeapon(_ itemId: String) {
        guard let info = ItemCatalog.all[itemId],
              let weapon = info.weapon,
              player.items.contains(itemId) else { return }
        if player.equippedWeapon == itemId { return }

        unequipWeapon(silent: true)
        applyWeaponBonus(weapon, sign: +1)
        player.equippedWeapon = itemId
        lastMessages = [EventMessage(
            text: "Tu portes maintenant : \(info.name).",
            kind: .info
        )]
        saveCurrentState()
    }

    /// Retire l'arme équipée (rendant son bonus). `silent` évite d'ajouter
    /// un message dans la marge — utilisé pendant `equipWeapon` quand on
    /// remplace une arme par une autre.
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

    /// Ajuste les stats du joueur selon le bonus de l'arme. `sign = +1`
    /// pour équiper, `−1` pour déséquiper. Les valeurs courantes sont
    /// clampées à 1 minimum.
    private func applyWeaponBonus(_ weapon: WeaponKind, sign: Int) {
        switch weapon {
        case .sharpened:
            // Lame classique, équilibrée : +1 Habileté.
            player.skill += 1 * sign
            player.skillMax += 1 * sign
        case .assassin:
            // Lame légère et précise — +1 Chance pour traduire le côté
            // "tu trouves l'angle mort". Différencie de l'épée du forgeron
            // pour que les deux armes ne se valent pas.
            player.luck += 1 * sign
            player.luckMax += 1 * sign
        case .cursed:
            // Le pari : gros bonus Habileté contre perte de Chance.
            player.skill += 2 * sign
            player.skillMax += 2 * sign
            player.luck += -1 * sign
            player.luckMax += -1 * sign
        }
        player.skill = max(1, player.skill)
        player.skillMax = max(1, player.skillMax)
        player.luck = max(1, player.luck)
        player.luckMax = max(1, player.luckMax)
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
            // InkSwift 2.0 doesn't expose per-choice tags. Les annotations
            // sont encodées en fin de texte de choix :
            //   - `★`         → option notable / conditionnelle (style or)
            //   - `[$<n>]`    → option payante de <n> pièces d'or — restera
            //                   visible mais grisée si le joueur n'a pas assez.
            // On extrait, on nettoie, on construit le `Choice`.
            return Self.parseChoice(rawText: opt.text, index: opt.index)
        }
        lastMessages = messages
        isEnded = !story.canContinue && story.options.isEmpty

        // Filet de sécurité : si une fin a été marquée via `# outcome: ...`
        // (death, honour, destruction, dark, transcendence), on traite la
        // partie comme finie et on efface la sauvegarde — même si Ink dit
        // encore `canContinue=true` pour une raison parasite (cas observé
        // sur la fin death où le knot ne laissait pas le runtime tomber
        // proprement sur END avant le check). Sans ça, on re-sauvegardait
        // l'état « écran de fin » et le menu proposait « Reprendre » qui
        // ramenait sur la page de fin.
        if isEnded || finalOutcome != nil {
            clearSavedState()
        } else {
            saveCurrentState()
        }
        // À chaque pause stable (ou à la fin), on re-vérifie les hauts faits :
        // c'est le point de passage le plus universel — items ramassés, combats
        // terminés, outcome posé… tout y est résolu.
        checkAchievements()
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
        // En plus de mettre à jour `currentChapter`, on déclenche une
        // transition cinématique (fondu + titre plein écran) si on
        // change vraiment de chapitre. La vue consomme le signal et le
        // reset à nil après son animation (~2.5 s).
        if let raw = tags["chapter"], let chap = Chapter(rawValue: raw) {
            let previous = currentChapter
            currentChapter = chap
            if chap != previous {
                pendingChapterTransition = chap
                // Drone d'ambiance par chapitre : on rebias le volume du
                // loop d'exploration pour évoquer l'atmosphère (village
                // aéré → tombeau oppressant). Ramp interne d'1.2s pour
                // ne pas claquer.
                AmbientAudio.shared.setChapterAmbience(chap)
            }
        }

        // illustration: <name> — affiche une planche pleine page que le
        // joueur ferme en tapant "Continuer". L'image attendue est
        // `illustration_<name>.jpg` dans le bundle.
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
                // Méta-progression : on compte les runs qui se sont
                // achevées sur autre chose qu'une mort. Sert au succès
                // « Tombeau revisité » (3+ runs complets cumulés).
                recordCompletedRun()
            }
        }

        // add_item: <id> ou add_item: <id1>,<id2>,…
        //
        // InkSwift expose `currentTags` comme un dict — donc deux lignes
        // `# add_item: X` + `# add_item: Y` dans le même knot s'écrasent
        // (seul le dernier survit). Pour permettre les pickups multiples,
        // on accepte la valeur comma-separated et on itère.
        //
        // Idempotence : certains items peuvent être débloqués via plusieurs
        // chemins indépendants (ex. `rumour_mortimer` proposé par
        // l'auberge ET par la sorcière). Si le joueur a déjà l'item, on
        // ré-affirme la VAR Ink (au cas où) mais on ne re-pousse PAS
        // message / popin / son — sinon on a la même rumeur annoncée deux
        // fois et le joueur a l'impression que le jeu se répète.
        if let raw = tags["add_item"] {
            let items = raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for item in items {
                let alreadyOwned = player.items.contains(item)
                player.items.insert(item)
                story.setVariable("has_\(item)", to: 1)
                // Item déjà possédé → on garde la VAR Ink à 1 (idempotent)
                // mais on n'ajoute aucun feedback UI/sonore : le joueur l'a
                // déjà vu lors du premier pickup.
                guard !alreadyOwned else { continue }
                // Marque l'item comme « non vu » pour afficher le badge
                // doré dans l'inventaire jusqu'à ce que le joueur ouvre
                // la feuille et le consulte.
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
                // Auto-équipe la première arme ramassée. Les armes suivantes
                // restent dans le sac : le joueur choisit explicitement de
                // changer s'il veut basculer (cf. InventoryView).
                if let info = ItemCatalog.all[item],
                   let weapon = info.weapon,
                   player.equippedWeapon == nil {
                    applyWeaponBonus(weapon, sign: +1)
                    player.equippedWeapon = item
                }
                // Pulse l'icône d'inventaire dans le HUD quand on ramasse un
                // consommable — c'est la classe d'item où il y a quelque
                // chose de "à faire" derrière (boire la potion).
                if ItemCatalog.all[item]?.consumable != nil {
                    inventoryPulse += 1
                }
            }
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
                kind: .loss,
                iconOverride: "coin"
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

        // stamina_bonus: <n> — permanent +n to Stamina max.
        // L'endurance courante monte d'autant pour ne pas faire ressentir
        // l'augmentation comme un soin manqué.
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

        // luck_bonus: <n> — permanent +n to Luck and LuckMax (n peut être
        // négatif pour les malédictions silencieuses, ex. mendiant ignoré).
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
                // Malédiction : ton-doux, message en italique discret,
                // pas de son joyeux. Le récit a déjà décrit ce qui s'est
                // passé — on ne mécanise pas la souffrance.
                let lost = abs(n)
                messages.append(EventMessage(
                    text: "Quelque chose en toi s'éteint un peu. Ta Chance recule de \(lost) point\(lost > 1 ? "s" : "").",
                    kind: .unlucky
                ))
                AmbientAudio.shared.play(.unlucky)
            }
        }

        // luck_restore: Luck reset to its maximum.
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

        // luck_test: -4 stamina on failure. Message générique : le contexte
        // (ex. "les lames jaillissent") est donné par le passage lui-même.
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

        // luck_grab_amulette: Mortimer special-case.
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

        // ending: victory | defeat — final jingle
        if let ending = tags["ending"] {
            switch ending {
            case "victory": AmbientAudio.shared.play(.victory)
            case "defeat":  AmbientAudio.shared.play(.death)
            default: break
            }
        }

        // Note historique : on avait ajouté ici un filet de sécurité
        // « si player.isDead et qu'aucun handler n'a fait le saut vers
        // death, jump à death ». Il provoquait une boucle infinie en lecture
        // du death knot lui-même (les tags d'outcome / ending peuvent être
        // émis sur un chunk différent du premier texte, donc finalOutcome
        // pouvait rester nil au moment du check). Chaque handler qui peut
        // amener stamina à 0 (damage, luck_test, luck_test_book,
        // luck_grab_amulette, resolveBattle .defeat) gère déjà son jump
        // explicitement — pas besoin de doublon.

        return false
    }

    // MARK: - Méta-progression (persistée hors save de run)

    /// Clés UserDefaults pour la méta-progression : ces données traversent
    /// les parties (contrairement à `saveKey` qui ne contient que la run
    /// courante et est invalidée à chaque mort / victoire / nouveau format).
    private static let kDiscoveredEndings = "tomb.meta.endings"
    private static let kDefeatedEnemies   = "tomb.meta.bestiary"
    private static let kAchievements      = "tomb.meta.achievements"
    private static let kCompletedRuns     = "tomb.meta.completed_runs"

    /// Marque une fin comme découverte et persiste. Appelé quand l'aventure
    /// se termine sur un knot taggé `# outcome: <id>`.
    private func recordDiscoveredEnding(_ outcome: FinalOutcome) {
        if discoveredEndings.insert(outcome).inserted {
            Self.persistDiscoveredEndings(discoveredEndings)
        }
    }

    /// Marque un ennemi comme vaincu et persiste. Appelé depuis
    /// `resolveBattle` sur victoire.
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

    /// Incrémente le compteur de runs terminées et persiste. Appelé une
    /// fois quand un outcome (autre que death) est posé en fin
    /// d'aventure.
    private func recordCompletedRun() {
        completedRuns += 1
        Self.persistCompletedRuns(completedRuns)
    }

    /// Re-évalue toutes les conditions et débloque les nouveaux hauts faits.
    /// Appelé à chaque event clé (fin d'`advance()`, victoire de combat,
    /// `useItem`). Émet un burst pour chaque déblocage, espacé de ~1.5 s
    /// si plusieurs tombent d'un coup.
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

    /// Évalue la condition d'un haut fait donné sur l'état courant du
    /// joueur / session. Les conditions "fin d'aventure" requièrent
    /// `isEnded` ou `finalOutcome` non-nil pour ne pas se déclencher trop tôt.
    private func achievementSatisfied(_ id: String) -> Bool {
        switch id {
        case AchievementsCatalog.ID.firstBlood:
            return battlesWon >= 1

        case AchievementsCatalog.ID.pacifist:
            // Mortimer phase 1 + 2 sont des combats obligatoires sur le
            // chemin honor (aucune option non-combat pour récupérer
            // l'amulette). Tolère donc jusqu'à 2 victoires.
            return finalOutcome == .honour && battlesWon <= 2

        case AchievementsCatalog.ID.ironMan:
            return finalOutcome != nil && finalOutcome != .death && potionsUsedThisRun == 0

        case AchievementsCatalog.ID.collector:
            return player.items.count >= 10

        case AchievementsCatalog.ID.cartographer:
            return discoveredEndings.count >= FinalOutcome.allCases.count

        case AchievementsCatalog.ID.bestiaryFull:
            // Les ennemis du bestiaire affichable (cf. BestiaryView.orderedIds)
            // forment le set "complet" — 17 entrées dont 2 optionnelles
            // (forest_lynx, marsh_wraith) qui demandent d'aller chercher
            // les chemins cachés.
            let required: Set<String> = [
                "goblin_scout", "forest_wolves", "forest_boar",
                "forest_lycanthrope", "forest_lynx",
                "marsh_serpent", "marsh_wraith",
                "tomb_ghoul",
                "skeleton_guardians", "gallery_skeletons", "flooded_eels",
                "tomb_basilisk", "treasure_guardian", "vengeful_spirit",
                "pit_skeletons", "mortimer_spectre_phase1",
                "mortimer_spectre_phase2"
            ]
            return required.isSubset(of: defeatedEnemies)

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
            // Doit avoir un outcome (run finie), pas une mort, et durée < 20 min.
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

    /// Étale les bursts d'achievement dans le temps quand plusieurs se
    /// débloquent ensemble — sinon ils s'écraseraient mutuellement en
    /// passant tous par `effectBurst` (un seul slot affiché à la fois).
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

    /// Bumpé à v12 avec l'ajout de `PlayerState.equippedWeapon` (slot
    /// d'arme), la conversion des potions / herbes en items consommables,
    /// et le retrait du tag `# skill_bonus:` sur les armes (le bonus est
    /// désormais dynamique selon l'arme portée). Les saves v11 décodent
    /// quand même mais le slot d'arme part vide.
    private static let saveKey = "tomb.save.v12"

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
        /// Optionnel pour rester compatible avec les saves v12 sans ce
        /// champ. À l'absence, on retombe sur 0 — le compteur reprend à zéro
        /// pour la partie en cours.
        let potionsUsedThisRun: Int?
        /// Optionnel : date de début de la run en cours. À l'absence (saves
        /// antérieures), le compteur de temps n'est pas affiché à la fin
        /// — pas critique, on évite juste un faux chiffre incohérent.
        let runStartedAt: Date?
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
            difficulty: difficulty,
            potionsUsedThisRun: potionsUsedThisRun,
            runStartedAt: runStartedAt
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
        potionsUsedThisRun = save.potionsUsedThisRun ?? 0
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

    /// File d'attente : un même tour de jeu peut générer plusieurs bursts
    /// (ex. `add_item` + `stamina_bonus` + `luck_bonus` sur la bénédiction du
    /// père Cassien). Sans queue, chaque nouvel appel à `showBurst` annulait
    /// l'animation en cours et seul le dernier était visible.
    private var burstQueue: [EffectBurst] = []
    private var burstDraining = false

    private func showBurst(_ burst: EffectBurst) {
        burstQueue.append(burst)
        guard !burstDraining else { return }
        // Important : on doit verrouiller AVANT de spawner la Task.
        // Sinon, deux appels synchrones à showBurst (ex. `add_item:
        // potion, compass`) voient burstDraining=false tous les deux,
        // spawnent chacun leur drain, et la deuxième écrase la première
        // popin avant qu'elle ait fini de jouer. Le joueur ne voyait
        // alors que le dernier item.
        burstDraining = true
        Task { @MainActor in
            await drainBurstQueue()
        }
    }

    /// Joue les bursts un par un, ~2 s par burst + 250 ms de respiration
    /// entre chaque. Boucle tant que la queue n'est pas vide (les bursts
    /// ajoutés en cours de route sont récupérés au tour suivant).
    @MainActor
    private func drainBurstQueue() async {
        defer { burstDraining = false }
        while !burstQueue.isEmpty {
            let next = burstQueue.removeFirst()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                effectBurst = next
            }
            // 2 s : le joueur a le temps de lire le titre + sous-titre
            // (ex. "Tu obtiens : Lame affûtée") avant que la popin
            // disparaisse. L'ancien 1.1 s passait trop vite quand
            // plusieurs items s'enchaînaient.
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

    /// Différe une mutation de stats (luck, stamina, items…) jusqu'à la
    /// fin de la chute des dés narratifs — au moment où le verdict
    /// apparaît dans l'overlay. Sans ça, les jauges baissaient
    /// instantanément alors que les dés n'avaient pas encore quitté la
    /// main, et le joueur voyait le résultat « avant l'heure ».
    ///
    /// 1900 ms = 1750 ms d'animation de chute (cf.
    /// `NarrativeLuckOverlay.task` qui révèle le verdict à 1750 ms) +
    /// 150 ms de marge pour que le chiffre du dé soit bien posé visuellement.
    private func deferLuckTestStatChange(_ change: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1900))
            change()
        }
    }

    // MARK: - Score & grade

    /// Durée écoulée depuis le début de la run, formatée en
    /// « 47 min 12 s » / « 1 h 23 min ». Nil si la run n'a pas démarré ou
    /// si la sauvegarde précédait l'ajout de `runStartedAt`. Capture le
    /// moment de l'appel — pour un affichage live, ré-évaluer
    /// périodiquement.
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
