//
//  PlayerStateTests.swift
//  Couvre `testLuck()` (les jets de Chance hors combat passent par ce
//  même point) et les accesseurs d'état basiques.
//

import XCTest
@testable import tomb

final class PlayerStateTests: XCTestCase {

    private func makePlayer(luck: Int = 8) -> PlayerState {
        PlayerState(
            skill: 9, skillMax: 9,
            stamina: 20, staminaMax: 20,
            luck: luck, luckMax: luck
        )
    }

    func test_testLuck_lowRoll_isLucky_andConsumesOnePoint() {
        var p = makePlayer(luck: 8)
        let (lucky, roll, threshold) = p.testLuck(roll: 5)

        XCTAssertTrue(lucky)
        XCTAssertEqual(roll, 5)
        XCTAssertEqual(threshold, 8, "Le seuil mémorisé est la Chance AVANT décrément")
        XCTAssertEqual(p.luck, 7, "Tout test de Chance coûte 1 point")
    }

    func test_testLuck_highRoll_isUnlucky_andConsumesOnePoint() {
        var p = makePlayer(luck: 5)
        let (lucky, _, _) = p.testLuck(roll: 12)

        XCTAssertFalse(lucky)
        XCTAssertEqual(p.luck, 4)
    }

    func test_testLuck_exactlyOnThreshold_isLucky() {
        var p = makePlayer(luck: 7)
        let (lucky, _, _) = p.testLuck(roll: 7)
        XCTAssertTrue(lucky, "Le jet ≤ seuil est chanceux (inclusif)")
    }

    func test_isDead_whenStaminaIsZero() {
        var p = makePlayer()
        p.stamina = 0
        XCTAssertTrue(p.isDead)
    }

    func test_isDead_whenStaminaIsNegative() {
        var p = makePlayer()
        p.stamina = -3
        XCTAssertTrue(p.isDead, "Stamina négative compte aussi comme mort")
    }

    func test_isAlive_atOnePoint() {
        var p = makePlayer()
        p.stamina = 1
        XCTAssertFalse(p.isDead)
    }
}
