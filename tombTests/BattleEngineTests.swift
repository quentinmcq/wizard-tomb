//
//  BattleEngineTests.swift
//  Couvre la logique pure du moteur de combat. Aucun random direct :
//  toutes les valeurs de dés sont injectées via les paramètres optionnels
//  des méthodes du moteur (`playerRoll`, `enemyRoll`, `luckRoll`) pour
//  garantir des assertions déterministes.
//

import XCTest
@testable import tomb

final class BattleEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Joueur basique pour les scénarios : Habileté 9, Endurance 20, Chance 8.
    private func makePlayer(skill: Int = 9,
                            stamina: Int = 20,
                            luck: Int = 8) -> PlayerState {
        PlayerState(
            skill: skill, skillMax: skill,
            stamina: stamina, staminaMax: stamina,
            luck: luck, luckMax: luck
        )
    }

    /// Ennemi standard : Habileté 7, Endurance 6, pas de bonus.
    private func makeEnemy(skill: Int = 7,
                           stamina: Int = 6,
                           damageBonus: Int = 0) -> Enemy {
        Enemy(id: "test_enemy", name: "Sbire d'essai",
              skill: skill, stamina: stamina,
              damageBonus: damageBonus)
    }

    private func makeBattle(_ enemy: Enemy,
                            fleeTarget: String? = nil) -> BattleState {
        BattleState(setup: BattleSetup(enemy: enemy, fleeTarget: fleeTarget))
    }

    // MARK: - Attack

    func test_attack_playerWins_dealsTwoDamageAndOffersLuck() {
        var player = makePlayer()         // skill 9 → total 9 + 12 = 21
        var battle = makeBattle(makeEnemy()) // skill 7 → total 7 + 4  = 11
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 12, enemyRoll: 4)

        XCTAssertEqual(battle.enemy.stamina, 4, "Joueur gagne → -2 PV ennemi")
        XCTAssertEqual(player.stamina, 20, "Joueur intact")
        XCTAssertEqual(battle.phase, .canTryLuckOffense)
    }

    func test_attack_enemyWins_dealsTwoDamageAndOffersLuckDefense() {
        var player = makePlayer()          // skill 9 → total 9 + 4 = 13
        var battle = makeBattle(makeEnemy()) // skill 7 → total 7 + 12 = 19
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 4, enemyRoll: 12)

        XCTAssertEqual(player.stamina, 18, "Ennemi gagne → -2 PV joueur")
        XCTAssertEqual(battle.enemy.stamina, 6)
        XCTAssertEqual(battle.phase, .canTryLuckDefense)
    }

    func test_attack_tie_noDamage_returnsToAwaiting() {
        var player = makePlayer()
        var battle = makeBattle(makeEnemy())
        // Même somme côté joueur et ennemi → égalité → parade.
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 5, enemyRoll: 7)  // 5+9=14 / 7+7=14

        XCTAssertEqual(player.stamina, 20)
        XCTAssertEqual(battle.enemy.stamina, 6)
        XCTAssertEqual(battle.phase, .awaitingAction)
    }

    func test_attack_killingBlow_endsInVictory() {
        var player = makePlayer()
        // Ennemi sur 2 PV : un coup réussi le finit.
        var battle = makeBattle(makeEnemy(stamina: 2))
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 12, enemyRoll: 2)

        XCTAssertEqual(battle.enemy.stamina, 0)
        XCTAssertEqual(battle.phase, .ended(.victory))
    }

    func test_attack_killingPlayer_endsInDefeat() {
        // Joueur sur 2 PV : un coup ennemi le tue.
        var player = makePlayer(stamina: 2)
        var battle = makeBattle(makeEnemy())
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 2, enemyRoll: 12)

        XCTAssertLessThanOrEqual(player.stamina, 0)
        XCTAssertEqual(battle.phase, .ended(.defeat))
    }

    func test_attack_damageBonusAppliedOnEnemyHit() {
        // Ennemi avec damageBonus +1 (lycanthrope) → 3 dégâts/coup.
        var player = makePlayer()
        var battle = makeBattle(makeEnemy(damageBonus: 1))
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 2, enemyRoll: 12)

        XCTAssertEqual(player.stamina, 17, "Bonus +1 → -3 PV au lieu de -2")
    }

    // MARK: - Luck offense

    func test_tryLuckOffense_lucky_dealsTwoExtraDamage() {
        var player = makePlayer(luck: 8)
        var battle = makeBattle(makeEnemy(stamina: 6))
        // Le moteur d'attaque vient juste de retirer 2 PV à l'ennemi.
        battle.enemy.stamina = 4
        BattleEngine.tryLuckOffense(state: &battle, player: &player, luckRoll: 5)

        XCTAssertEqual(player.luck, 7, "1 point de Chance consommé")
        XCTAssertEqual(battle.enemy.stamina, 2, "2 dégâts supplémentaires")
    }

    func test_tryLuckOffense_unlucky_reducesDamageToOne() {
        var player = makePlayer(luck: 3)
        var battle = makeBattle(makeEnemy(stamina: 6))
        battle.enemy.stamina = 4
        BattleEngine.tryLuckOffense(state: &battle, player: &player, luckRoll: 12)

        XCTAssertEqual(player.luck, 2)
        XCTAssertEqual(battle.enemy.stamina, 5,
                       "Dégâts réduits à 1 → on rend 1 PV à l'ennemi")
    }

    // MARK: - Luck defense

    func test_tryLuckDefense_lucky_savesOnePoint() {
        var player = makePlayer(luck: 8, stamina: 18)  // vient d'encaisser 2 PV
        var battle = makeBattle(makeEnemy())
        BattleEngine.tryLuckDefense(state: &battle, player: &player, luckRoll: 5)

        XCTAssertEqual(player.luck, 7)
        XCTAssertEqual(player.stamina, 19, "Chance amortit : +1 PV récupéré")
    }

    func test_tryLuckDefense_unlucky_costsOneMorePoint() {
        var player = makePlayer(luck: 3, stamina: 18)
        var battle = makeBattle(makeEnemy())
        BattleEngine.tryLuckDefense(state: &battle, player: &player, luckRoll: 12)

        XCTAssertEqual(player.luck, 2)
        XCTAssertEqual(player.stamina, 17, "Chance ratée : -1 PV supplémentaire")
    }

    // MARK: - Skip luck

    func test_skipLuck_returnsToAwaitingAction() {
        var battle = makeBattle(makeEnemy())
        battle.phase = .canTryLuckOffense
        BattleEngine.skipLuck(state: &battle)
        XCTAssertEqual(battle.phase, .awaitingAction)
    }

    // MARK: - Flee

    func test_flee_lucky_endsAsFledToTarget() {
        var player = makePlayer(luck: 8)
        var battle = makeBattle(makeEnemy(), fleeTarget: "forest_clearing")
        BattleEngine.flee(state: &battle, player: &player, luckRoll: 5)

        XCTAssertTrue(battle.fleeUsed)
        XCTAssertEqual(battle.phase, .ended(.fled(toPassage: "forest_clearing")))
        XCTAssertEqual(player.stamina, 20, "Pas de dégâts à la fuite réussie")
    }

    func test_flee_unlucky_takesFreeHitAndStaysInCombat() {
        var player = makePlayer(luck: 3, stamina: 18)
        var battle = makeBattle(makeEnemy(), fleeTarget: "elsewhere")
        BattleEngine.flee(state: &battle, player: &player, luckRoll: 12)

        XCTAssertTrue(battle.fleeUsed)
        XCTAssertEqual(player.stamina, 16, "Coup gratuit : -2 PV")
        XCTAssertEqual(battle.phase, .awaitingAction)
    }

    func test_flee_unluckyAndKills_endsInDefeat() {
        var player = makePlayer(luck: 3, stamina: 2)
        var battle = makeBattle(makeEnemy(), fleeTarget: "elsewhere")
        BattleEngine.flee(state: &battle, player: &player, luckRoll: 12)

        XCTAssertLessThanOrEqual(player.stamina, 0)
        XCTAssertEqual(battle.phase, .ended(.defeat))
    }

    func test_flee_withoutTarget_isNoOp() {
        var player = makePlayer()
        var battle = makeBattle(makeEnemy(), fleeTarget: nil)
        BattleEngine.flee(state: &battle, player: &player, luckRoll: 5)

        XCTAssertFalse(battle.fleeUsed,
                       "Pas de fleeTarget → la fuite est inopérante")
        XCTAssertEqual(battle.phase, .awaitingAction)
    }

    // MARK: - Modifiers consommés

    func test_attack_consumesPlayerSkillBonus() {
        var player = makePlayer(skill: 6)
        var battle = makeBattle(makeEnemy(skill: 7))
        battle.playerSkillBonus = 5     // boost transitoire

        // Avec le boost : 6 + 5 + 6 = 17 vs 7 + 6 = 13 → joueur gagne.
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 6, enemyRoll: 6)
        XCTAssertEqual(battle.enemy.stamina, 4)
        XCTAssertEqual(battle.playerSkillBonus, 0, "Boost consommé en un round")
    }

    func test_attack_consumesEnemySkillPenalty() {
        var player = makePlayer(skill: 7)
        var battle = makeBattle(makeEnemy(skill: 9))
        battle.enemySkillPenalty = 4    // huile / eau bénite

        // Joueur : 6 + 7 = 13 ; ennemi : max(0, 9 - 4) + 6 = 11 → joueur gagne.
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 6, enemyRoll: 6)
        XCTAssertEqual(battle.enemy.stamina, 4)
        XCTAssertEqual(battle.enemySkillPenalty, 0,
                       "Pénalité consommée en un round")
    }
}
