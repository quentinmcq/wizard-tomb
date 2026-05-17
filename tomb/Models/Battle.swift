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

    init(setup: BattleSetup) {
        self.enemy = setup.enemy
        self.fleeTarget = setup.fleeTarget
        // No intro line in the log: the enemy card on top already shows
        // name + Skill + Stamina.
    }
}

// MARK: - Engine

enum BattleEngine {

    /// Resolves an attack round. Emits ONE readable log entry, no jargon
    /// (the numbers are already visible in the dice and the EnemyCard).
    static func attack(state: inout BattleState,
                       player: inout PlayerState,
                       playerRoll: Int? = nil,
                       enemyRoll: Int? = nil) {
        let pSum = playerRoll ?? roll2d6()
        let eSum = enemyRoll ?? roll2d6()
        let playerAttack = pSum + player.skill
        let enemyAttack  = eSum + state.enemy.skill
        let enemyName    = state.enemy.name

        if playerAttack > enemyAttack {
            state.enemy.stamina -= 2
            state.log.append(BattleLogEntry(
                text: "Tu touches ! \(enemyName) perd 2 points d'Endurance.",
                kind: .hitDealt
            ))
            transitionAfterPlayerHit(state: &state, player: player)
        } else if enemyAttack > playerAttack {
            player.stamina -= 2
            state.log.append(BattleLogEntry(
                text: "\(enemyName) te touche. Tu perds 2 points d'Endurance.",
                kind: .hitTaken
            ))
            transitionAfterEnemyHit(state: &state, player: player)
        } else {
            state.log.append(BattleLogEntry(
                text: "Égalité. Vos lames se croisent sans toucher.",
                kind: .miss
            ))
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
            state.log.append(BattleLogEntry(
                text: "Coup magistral ! \(enemyName) perd 2 points d'Endurance supplémentaires.",
                kind: .lucky
            ))
        } else {
            // Damage reduced to 1: give 1 stamina back to the enemy.
            state.enemy.stamina = min(state.enemy.stamina + 1, state.enemy.staminaMax)
            state.log.append(BattleLogEntry(
                text: "Ton coup ne fait qu'effleurer ta cible : 1 dégât au lieu de 2.",
                kind: .unlucky
            ))
        }
        finalizeAfterLuck(state: &state, player: player)
    }

    /// Test Luck after taking a hit: -1 damage on lucky, +1 damage on unlucky.
    static func tryLuckDefense(state: inout BattleState,
                               player: inout PlayerState,
                               luckRoll: Int? = nil) {
        let (lucky, _, _) = player.testLuck(roll: luckRoll)
        if lucky {
            player.stamina = min(player.stamina + 1, player.staminaMax)
            state.log.append(BattleLogEntry(
                text: "Tu amortis le coup : tu ne perds qu'1 point d'Endurance.",
                kind: .lucky
            ))
        } else {
            player.stamina -= 1
            state.log.append(BattleLogEntry(
                text: "Le coup s'enfonce profondément : 3 points d'Endurance perdus en tout.",
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
