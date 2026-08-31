import XCTest
@testable import tomb

final class BattleEngineTests: XCTestCase {
    // MARK: - Helpers

    private func makePlayer(skill: Int = 9,
                            stamina: Int = 20,
                            luck: Int = 8) -> PlayerState {
        PlayerState(
            skill: skill, skillMax: skill,
            stamina: stamina, staminaMax: stamina,
            luck: luck, luckMax: luck
        )
    }

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
        var player = makePlayer()
        var battle = makeBattle(makeEnemy())
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 12, enemyRoll: 4)

        XCTAssertEqual(battle.enemy.stamina, 4, "Joueur gagne → -2 PV ennemi")
        XCTAssertEqual(player.stamina, 20, "Joueur intact")
        XCTAssertEqual(battle.phase, .canTryLuckOffense)
    }

    func test_attack_enemyWins_dealsTwoDamageAndOffersLuckDefense() {
        var player = makePlayer()
        var battle = makeBattle(makeEnemy())
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 4, enemyRoll: 12)

        XCTAssertEqual(player.stamina, 18, "Ennemi gagne → -2 PV joueur")
        XCTAssertEqual(battle.enemy.stamina, 6)
        XCTAssertEqual(battle.phase, .canTryLuckDefense)
    }

    func test_attack_tie_noDamage_returnsToAwaiting() {
        var player = makePlayer()
        var battle = makeBattle(makeEnemy())
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 5, enemyRoll: 7)

        XCTAssertEqual(player.stamina, 20)
        XCTAssertEqual(battle.enemy.stamina, 6)
        XCTAssertEqual(battle.phase, .awaitingAction)
    }

    func test_attack_killingBlow_endsInVictory() {
        var player = makePlayer()
        var battle = makeBattle(makeEnemy(stamina: 2))
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 12, enemyRoll: 2)

        XCTAssertEqual(battle.enemy.stamina, 0)
        XCTAssertEqual(battle.phase, .ended(.victory))
    }

    func test_attack_killingPlayer_endsInDefeat() {
        var player = makePlayer(stamina: 2)
        var battle = makeBattle(makeEnemy())
        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 2, enemyRoll: 12)

        XCTAssertLessThanOrEqual(player.stamina, 0)
        XCTAssertEqual(battle.phase, .ended(.defeat))
    }

    func test_attack_damageBonusAppliedOnEnemyHit() {
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
        var player = makePlayer(stamina: 18, luck: 8)
        var battle = makeBattle(makeEnemy())
        BattleEngine.tryLuckDefense(state: &battle, player: &player, luckRoll: 5)

        XCTAssertEqual(player.luck, 7)
        XCTAssertEqual(player.stamina, 19, "Chance amortit : +1 PV récupéré")
    }

    func test_tryLuckDefense_unlucky_costsOneMorePoint() {
        var player = makePlayer(stamina: 18, luck: 3)
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
        var player = makePlayer(stamina: 18, luck: 3)
        var battle = makeBattle(makeEnemy(), fleeTarget: "elsewhere")
        BattleEngine.flee(state: &battle, player: &player, luckRoll: 12)

        XCTAssertTrue(battle.fleeUsed)
        XCTAssertEqual(player.stamina, 16, "Coup gratuit : -2 PV")
        XCTAssertEqual(battle.phase, .awaitingAction)
    }

    func test_flee_unluckyAndKills_endsInDefeat() {
        var player = makePlayer(stamina: 2, luck: 3)
        var battle = makeBattle(makeEnemy(), fleeTarget: "elsewhere")
        BattleEngine.flee(state: &battle, player: &player, luckRoll: 12)

        XCTAssertLessThanOrEqual(player.stamina, 0)
        XCTAssertEqual(battle.phase, .ended(.defeat))
    }

    // MARK: - Variantes de texte

    // ⚠️ Régression : `wild_boar`, `mortimer` et `mortimer_phase2` ne
    // correspondaient à aucune entrée du catalogue, donc les répliques sur
    // mesure du sanglier et des deux phases du boss ne se déclenchaient
    // jamais — le combat retombait en silence sur les lignes génériques.
    func test_customVariantIdsExistInCatalog() {
        for id in BattleEngine.customisedEnemyIDs {
            XCTAssertNotNil(EnemyCatalog.all[id],
                            "\(id) a des répliques sur mesure mais n'existe pas au catalogue")
            XCTAssertTrue(BattleEngine.hasCustomVariants(for: id),
                          "\(id) devrait avoir des répliques des deux côtés")
        }
    }

    func test_enemiesWithoutCustomVariantsFallBackToGenericLines() {
        XCTAssertFalse(BattleEngine.hasCustomVariants(for: "goblin_scout"))
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
        battle.playerSkillBonus = 5

        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 6, enemyRoll: 6)
        XCTAssertEqual(battle.enemy.stamina, 4)
        XCTAssertEqual(battle.playerSkillBonus, 0, "Boost consommé en un round")
    }

    func test_attack_consumesEnemySkillPenalty() {
        var player = makePlayer(skill: 7)
        var battle = makeBattle(makeEnemy(skill: 9))
        battle.enemySkillPenalty = 4

        BattleEngine.attack(state: &battle, player: &player,
                            playerRoll: 6, enemyRoll: 6)
        XCTAssertEqual(battle.enemy.stamina, 4)
        XCTAssertEqual(battle.enemySkillPenalty, 0,
                       "Pénalité consommée en un round")
    }
}
