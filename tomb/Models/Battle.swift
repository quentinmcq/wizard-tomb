//
//  Battle.swift
//  Turn-based combat engine in the Fighting Fantasy style.
//
//  Rules applied:
//   - Each round: 2d6 + Skill for both fighters. Higher attack roll hits for
//     2 stamina. Tie = parry, no damage.
//   - After landing a hit: Test Luck for +2 damage on lucky, only 1 damage
//     on unlucky.
//   - After taking a hit: Test Luck for -1 damage on lucky, +1 damage on
//     unlucky.
//   - Each Luck test reduces Luck by 1 (handled inside `testLuck()`).
//

import Foundation

// MARK: - Outcome

enum BattleOutcome: Equatable {
    case victory
    case defeat
    case fled(toPassage: String)
}

// MARK: - Phases

enum BattlePhase: Equatable {
    case awaitingAction
    case canTryLuckOffense
    case canTryLuckDefense
    case ended(BattleOutcome)
}

// MARK: - Log

struct BattleLogEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: Kind

    enum Kind { case info, hitDealt, hitTaken, miss, lucky, unlucky, end }
}

// MARK: - State

struct BattleState {
    var enemy: Enemy
    var phase: BattlePhase = .awaitingAction
    var log: [BattleLogEntry] = []
    let fleeTarget: String?
    /// True dès que le joueur a tenté de fuir une fois (qu'il ait réussi ou
    /// pas). On masque alors le bouton "Tenter de fuir" — pas de seconde
    /// chance, l'ennemi est sur ses gardes.
    var fleeUsed: Bool = false
    /// Bonus d'Habileté appliqué au prochain `attack()`, puis consommé.
    /// Sert aux items combat (witch_fetish, etc.) qui boostent un seul
    /// round avant d'être perdus.
    var playerSkillBonus: Int = 0
    /// Pénalité d'Habileté appliquée à l'ennemi au prochain `attack()`,
    /// puis consommée. Pendant pour les items qui affaiblissent (eau
    /// bénite, huile noire…).
    var enemySkillPenalty: Int = 0

    init(setup: BattleSetup) {
        self.enemy = setup.enemy
        self.fleeTarget = setup.fleeTarget
        // No intro line in the log: the enemy card on top already shows
        // name + Skill + Stamina.
    }
}

// MARK: - Engine

enum BattleEngine {

    // MARK: Variantes de texte
    //
    // Pour éviter la répétition « Tu touches ! X perd 2 points d'Endurance. »
    // round après round, on tire une variante au hasard parmi les listes
    // ci-dessous. Quelques ennemis emblématiques (sanglier, lycanthrope,
    // Mortimer) ont en plus des lignes personnalisées qui passent en
    // priorité — voir `customHitDealt(for:)` / `customHitTaken(for:)`.

    private static let hitDealtVariants: [String] = [
        "Tu touches ! {enemy} perd 2 points d'Endurance.",
        "Ta lame trouve son ouverture. {enemy} encaisse 2 points d'Endurance.",
        "Coup net : {enemy} chancelle, 2 points d'Endurance en moins.",
        "Tu frappes au bon moment. {enemy} perd 2 points d'Endurance.",
        "Ton arme s'enfonce. {enemy} encaisse 2 points d'Endurance."
    ]

    private static let hitTakenVariants: [String] = [
        "{enemy} te touche. Tu perds {dmg} points d'Endurance.",
        "{enemy} esquive ta garde et te frappe : -{dmg} Endurance.",
        "Tu pares trop tard. {enemy} t'atteint : -{dmg} Endurance.",
        "{enemy} t'ouvre une plaie. Tu perds {dmg} points d'Endurance.",
        "Le coup de {enemy} passe ta défense : -{dmg} Endurance."
    ]

    private static let missVariants: [String] = [
        "Égalité. Vos lames se croisent sans toucher.",
        "Vos attaques se neutralisent dans un fracas.",
        "Personne ne cède. La passe d'armes s'achève à mains vides.",
        "Vos coups se croisent. Aucun ne touche.",
        "Les lames mordent l'acier, pas la chair."
    ]

    private static let luckyOffenseVariants: [String] = [
        "Coup magistral ! {enemy} perd 2 points d'Endurance supplémentaires.",
        "La chance guide ton bras. {enemy} encaisse 2 points d'Endurance de plus.",
        "Tu touches un point faible. {enemy} perd 2 points d'Endurance en plus."
    ]

    private static let unluckyOffenseVariants: [String] = [
        "Ton coup ne fait qu'effleurer ta cible : 1 dégât au lieu de 2.",
        "Ta lame ripe sur la garde adverse : 1 dégât au lieu de 2.",
        "Le coup glisse sur l'armure : 1 dégât au lieu de 2."
    ]

    /// Lignes spécifiques quand le joueur touche certains ennemis. Si
    /// l'`id` n'est pas listé, on retombe sur `hitDealtVariants`.
    private static func customHitDealt(for enemyID: String) -> [String]? {
        switch enemyID {
        case "wild_boar":
            return [
                "Tu plantes ta lame dans son flanc. Le sanglier titane recule en grognant. -2 Endurance.",
                "Le sanglier encaisse et secoue sa hure. -2 Endurance."
            ]
        case "forest_lycanthrope":
            return [
                "Ta lame ouvre la fourrure. Le lycanthrope rugit. -2 Endurance.",
                "Tu trouves une faille entre les griffes. -2 Endurance."
            ]
        case "mortimer", "mortimer_phase2":
            return [
                "Ta lame coupe l'air froid autour du sorcier. -2 Endurance.",
                "Mortimer vacille. Sa robe se déchire. -2 Endurance."
            ]
        case "marsh_serpent":
            return [
                "Tu trouves l'angle entre les écailles. -2 Endurance.",
                "Le serpent siffle, blessé. -2 Endurance."
            ]
        case "treasure_guardian":
            return [
                "Ta lame fait éclater un éclat de pierre. -2 Endurance.",
                "Une fêlure court dans la statue. -2 Endurance."
            ]
        default:
            return nil
        }
    }

    /// Lignes spécifiques quand l'ennemi touche le joueur.
    private static func customHitTaken(for enemyID: String) -> [String]? {
        switch enemyID {
        case "wild_boar":
            return [
                "Le sanglier charge ! Tu prends son boutoir de plein fouet. -{dmg} Endurance.",
                "Sa hure t'envoie au sol. -{dmg} Endurance."
            ]
        case "forest_lycanthrope":
            return [
                "Les griffes du lycanthrope te lacèrent. -{dmg} Endurance.",
                "Une morsure profonde. -{dmg} Endurance."
            ]
        case "mortimer", "mortimer_phase2":
            return [
                "Un éclair sombre te frappe en pleine poitrine. -{dmg} Endurance.",
                "Le souffle spectral du sorcier te glace. -{dmg} Endurance."
            ]
        case "marsh_serpent":
            return [
                "Le serpent te happe la jambe. -{dmg} Endurance.",
                "Un crochet acéré transperce ta garde. -{dmg} Endurance."
            ]
        case "treasure_guardian":
            return [
                "La poigne de pierre se referme sur ton bras. -{dmg} Endurance.",
                "Le gardien t'écrase contre la paroi. -{dmg} Endurance."
            ]
        default:
            return nil
        }
    }

    /// Choisit une variante aléatoire et remplace les marqueurs `{enemy}`
    /// et `{dmg}`. Si la liste passée est `nil` ou vide, retombe sur la
    /// liste générique fournie en `fallback`.
    private static func pickVariant(_ custom: [String]?,
                                     fallback: [String],
                                     enemy: String,
                                     damage: Int? = nil) -> String {
        let pool = (custom?.isEmpty == false) ? custom! : fallback
        var line = pool.randomElement() ?? fallback.first ?? ""
        line = line.replacingOccurrences(of: "{enemy}", with: enemy)
        if let dmg = damage {
            line = line.replacingOccurrences(of: "{dmg}", with: String(dmg))
        }
        return line
    }

    /// Resolves an attack round. Emits ONE readable log entry, no jargon
    /// (the numbers are already visible in the dice and the EnemyCard).
    static func attack(state: inout BattleState,
                       player: inout PlayerState,
                       playerRoll: Int? = nil,
                       enemyRoll: Int? = nil) {
        let pSum = playerRoll ?? roll2d6()
        let eSum = enemyRoll ?? roll2d6()
        // Modificateurs à usage unique posés par les items combat
        // (witch_fetish, holy_water, necro_oil). Consommés à chaque
        // résolution d'attaque pour qu'ils ne durent qu'un round.
        let playerAttack = pSum + player.skill + state.playerSkillBonus
        let enemyAttack  = eSum + max(0, state.enemy.skill - state.enemySkillPenalty)
        state.playerSkillBonus = 0
        state.enemySkillPenalty = 0
        let enemyName    = state.enemy.name
        let enemyID      = state.enemy.id

        if playerAttack > enemyAttack {
            state.enemy.stamina -= 2
            let line = pickVariant(customHitDealt(for: enemyID),
                                    fallback: hitDealtVariants,
                                    enemy: enemyName)
            state.log.append(BattleLogEntry(text: line, kind: .hitDealt))
            transitionAfterPlayerHit(state: &state, player: player)
        } else if enemyAttack > playerAttack {
            // Dégâts de base = 2, +damageBonus si l'ennemi a une aptitude
            // offensive (griffes acérées, poigne de pierre…).
            let dmg = 2 + state.enemy.damageBonus
            player.stamina -= dmg
            let line = pickVariant(customHitTaken(for: enemyID),
                                    fallback: hitTakenVariants,
                                    enemy: enemyName,
                                    damage: dmg)
            state.log.append(BattleLogEntry(text: line, kind: .hitTaken))
            transitionAfterEnemyHit(state: &state, player: player)
        } else {
            let line = missVariants.randomElement() ?? missVariants[0]
            state.log.append(BattleLogEntry(text: line, kind: .miss))
            state.phase = .awaitingAction
        }
    }

    /// Test Luck after dealing a hit: +2 damage on lucky, -1 damage on unlucky.
    static func tryLuckOffense(state: inout BattleState,
                               player: inout PlayerState,
                               luckRoll: Int? = nil) {
        let (lucky, _, _) = player.testLuck(roll: luckRoll)
        let enemyName = state.enemy.name
        if lucky {
            state.enemy.stamina -= 2
            let line = pickVariant(nil, fallback: luckyOffenseVariants, enemy: enemyName)
            state.log.append(BattleLogEntry(text: line, kind: .lucky))
        } else {
            // Damage reduced to 1: give 1 stamina back to the enemy.
            state.enemy.stamina = min(state.enemy.stamina + 1, state.enemy.staminaMax)
            let line = pickVariant(nil, fallback: unluckyOffenseVariants, enemy: enemyName)
            state.log.append(BattleLogEntry(text: line, kind: .unlucky))
        }
        finalizeAfterLuck(state: &state, player: player)
    }

    /// Test Luck after taking a hit: -1 damage on lucky, +1 damage on unlucky.
    /// Le total dépend du `damageBonus` de l'ennemi : un lycanthrope qui
    /// passe (+1 base) infligera 2 / 3 / 4 selon le jet de Chance.
    static func tryLuckDefense(state: inout BattleState,
                               player: inout PlayerState,
                               luckRoll: Int? = nil) {
        let (lucky, _, _) = player.testLuck(roll: luckRoll)
        let baseDmg = 2 + state.enemy.damageBonus
        if lucky {
            player.stamina = min(player.stamina + 1, player.staminaMax)
            let total = baseDmg - 1
            state.log.append(BattleLogEntry(
                text: "Tu amortis le coup : \(total) point\(total > 1 ? "s" : "") d'Endurance perdu\(total > 1 ? "s" : "") en tout.",
                kind: .lucky
            ))
        } else {
            player.stamina -= 1
            let total = baseDmg + 1
            state.log.append(BattleLogEntry(
                text: "Le coup s'enfonce profondément : \(total) points d'Endurance perdus en tout.",
                kind: .unlucky
            ))
        }
        finalizeAfterLuck(state: &state, player: player)
    }

    static func skipLuck(state: inout BattleState) {
        state.phase = .awaitingAction
    }

    /// Attempt to flee: Test Luck. If lucky, leave combat for `fleeTarget`.
    /// If unlucky, the enemy gets a free hit (2 stamina) while the player
    /// turns their back.
    static func flee(state: inout BattleState,
                     player: inout PlayerState,
                     luckRoll: Int? = nil) {
        guard let target = state.fleeTarget else { return }
        // Une seule tentative possible : qu'elle réussisse ou échoue, le
        // bouton "Tenter de fuir" disparaît ensuite.
        state.fleeUsed = true
        let (lucky, _, _) = player.testLuck(roll: luckRoll)
        if lucky {
            state.log.append(BattleLogEntry(
                text: "Tu prends la fuite sans encombre.",
                kind: .end
            ))
            state.phase = .ended(.fled(toPassage: target))
        } else {
            player.stamina -= 2
            state.log.append(BattleLogEntry(
                text: "Tu trébuches : \(state.enemy.name) en profite pour te frapper dans le dos. Tu perds 2 points d'Endurance.",
                kind: .hitTaken
            ))
            if player.stamina <= 0 {
                state.log.append(BattleLogEntry(
                    text: "Tu t'effondres.",
                    kind: .end
                ))
                state.phase = .ended(.defeat)
            } else {
                state.phase = .awaitingAction
            }
        }
    }

    // MARK: - Transitions

    private static func transitionAfterPlayerHit(state: inout BattleState,
                                                  player: PlayerState) {
        if state.enemy.stamina <= 0 {
            state.log.append(BattleLogEntry(
                text: "\(state.enemy.name) s'écroule à tes pieds.",
                kind: .end
            ))
            state.phase = .ended(.victory)
        } else if player.luck > 0 {
            state.phase = .canTryLuckOffense
        } else {
            state.phase = .awaitingAction
        }
    }

    private static func transitionAfterEnemyHit(state: inout BattleState,
                                                 player: PlayerState) {
        if player.stamina <= 0 {
            state.log.append(BattleLogEntry(
                text: "Tu t'effondres.",
                kind: .end
            ))
            state.phase = .ended(.defeat)
        } else if player.luck > 0 {
            state.phase = .canTryLuckDefense
        } else {
            state.phase = .awaitingAction
        }
    }

    private static func finalizeAfterLuck(state: inout BattleState,
                                           player: PlayerState) {
        if state.enemy.stamina <= 0 {
            state.log.append(BattleLogEntry(
                text: "\(state.enemy.name) s'écroule à tes pieds.",
                kind: .end
            ))
            state.phase = .ended(.victory)
        } else if player.stamina <= 0 {
            state.log.append(BattleLogEntry(
                text: "Tu t'effondres.",
                kind: .end
            ))
            state.phase = .ended(.defeat)
        } else {
            state.phase = .awaitingAction
        }
    }
}
