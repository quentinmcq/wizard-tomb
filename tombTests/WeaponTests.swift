import XCTest
@testable import tomb

final class WeaponTests: XCTestCase {
    private func makePlayer(skill: Int = 9, luck: Int = 8) -> PlayerState {
        PlayerState(
            skill: skill, skillMax: skill,
            stamina: 20, staminaMax: 20,
            luck: luck, luckMax: luck
        )
    }

    // MARK: - Réversibilité

    func test_equipThenUnequip_isExactlyNeutral() {
        for weapon in WeaponKind.allCases {
            var p = makePlayer()
            let before = p
            p.applyWeaponBonus(weapon, sign: +1)
            p.applyWeaponBonus(weapon, sign: -1)

            XCTAssertEqual(p.skill, before.skill, "\(weapon) : Habileté dérive")
            XCTAssertEqual(p.skillMax, before.skillMax, "\(weapon) : HabiletéMax dérive")
            XCTAssertEqual(p.luck, before.luck, "\(weapon) : Chance dérive")
            XCTAssertEqual(p.luckMax, before.luckMax, "\(weapon) : ChanceMax dérive")
        }
    }

    // ⚠️ Régression : avec luck = 1, l'ancien `max(1, luck)` absorbait le
    // malus de la lame maudite à l'équipement puis le rendait au retrait,
    // offrant +1 Chance permanente à chaque cycle.
    func test_cursedBladeCycling_grantsNoFreeLuck() {
        var p = makePlayer(luck: 1)
        let before = p
        for _ in 0..<10 where p.canEquip(.cursed) {
            p.applyWeaponBonus(.cursed, sign: +1)
            p.applyWeaponBonus(.cursed, sign: -1)
        }
        XCTAssertEqual(p.luck, before.luck)
        XCTAssertEqual(p.luckMax, before.luckMax)
    }

    // MARK: - Garde-fou

    func test_canEquip_refusesWhenLuckMaxWouldFallToZero() {
        let p = makePlayer(luck: 1)
        XCTAssertFalse(p.canEquip(.cursed),
                       "ChanceMax tomberait à 0 : l'arme doit être refusée")
    }

    func test_canEquip_allowsWhenMarginIsSufficient() {
        let p = makePlayer(luck: 2)
        XCTAssertTrue(p.canEquip(.cursed))
    }

    func test_canEquip_alwaysTrueForBonusOnlyWeapons() {
        let p = makePlayer(skill: 1, luck: 1)
        XCTAssertTrue(p.canEquip(.sharpened))
        XCTAssertTrue(p.canEquip(.assassin))
    }

    // MARK: - Valeurs des bonus

    func test_weaponDeltas_matchCatalogueDescriptions() {
        XCTAssertEqual(WeaponKind.sharpened.delta.skill, 1)
        XCTAssertEqual(WeaponKind.sharpened.delta.luck, 0)
        XCTAssertEqual(WeaponKind.assassin.delta.skill, 0)
        XCTAssertEqual(WeaponKind.assassin.delta.luck, 1)
        XCTAssertEqual(WeaponKind.cursed.delta.skill, 2)
        XCTAssertEqual(WeaponKind.cursed.delta.luck, -1)
    }

    func test_everyCatalogueWeaponIsReachable() {
        let declared = Set(ItemCatalog.all.values.compactMap { $0.weapon })
        XCTAssertEqual(declared, Set(WeaponKind.allCases),
                       "Un type d'arme n'est porté par aucun objet du catalogue")
    }
}
