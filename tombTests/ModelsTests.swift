import XCTest
@testable import tomb

final class ModelsTests: XCTestCase {
    // MARK: - FinalOutcome

    func test_FinalOutcome_rawValuesStableForInkAndSaves() {
        XCTAssertEqual(FinalOutcome.honour.rawValue, "honour")
        XCTAssertEqual(FinalOutcome.destruction.rawValue, "destruction")
        XCTAssertEqual(FinalOutcome.dark.rawValue, "dark")
        XCTAssertEqual(FinalOutcome.transcendence.rawValue, "transcendence")
        XCTAssertEqual(FinalOutcome.death.rawValue, "death")
    }

    func test_FinalOutcome_eachHasTitleAndBlurb() {
        for outcome in FinalOutcome.allCases {
            XCTAssertFalse(outcome.title.isEmpty,
                           "Titre manquant pour \(outcome)")
            XCTAssertFalse(outcome.blurb.isEmpty,
                           "Blurb manquant pour \(outcome)")
        }
    }

    // MARK: - Chapter

    func test_Chapter_rawValuesStableForInkAndSaves() {
        let expected: [Chapter: String] = [
            .village: "village",
            .forest: "forest",
            .marsh: "marsh",
            .ruins: "ruins",
            .tomb: "tomb",
            .chamber: "chamber",
            .homecoming: "homecoming",
            .ending: "ending"
        ]
        for (chap, raw) in expected {
            XCTAssertEqual(chap.rawValue, raw)
        }
    }

    func test_Chapter_eachHasTitleAndShortTitle() {
        for chap in Chapter.allCases {
            XCTAssertFalse(chap.title.isEmpty)
            XCTAssertFalse(chap.shortTitle.isEmpty)
            XCTAssertTrue(chap.title.count >= chap.shortTitle.count,
                          "Le shortTitle doit être plus compact que le titre complet")
        }
    }

    // MARK: - StatTooltipKind (sécurise l'icône utilisée)

    func test_StatTooltipKind_iconNamesMatchAssets() {
        XCTAssertEqual(StatTooltipKind.skill.icon, "ability")
        XCTAssertEqual(StatTooltipKind.stamina.icon, "life")
        XCTAssertEqual(StatTooltipKind.luck.icon, "luck")
    }

    func test_StatTooltipKind_eachHasSummaryAndDetail() {
        for kind: StatTooltipKind in [.skill, .stamina, .luck] {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.summary.isEmpty)
            XCTAssertGreaterThan(kind.detail.count, 40,
                                 "Le détail doit vraiment expliquer (>40 chars)")
        }
    }

    // MARK: - Catalogue du bestiaire
    //
    // La liste vit désormais dans `EnemyCatalog` et alimente à la fois
    // l'affichage du bestiaire et la condition du haut fait « Le grand
    // livre ». Une entrée mal orthographiée rendrait le succès
    // définitivement inatteignable sans que rien ne le signale.

    func test_bestiaryOrder_referencesOnlyRealEnemies() {
        for id in EnemyCatalog.bestiaryOrder {
            XCTAssertNotNil(EnemyCatalog.all[id],
                            "\(id) est listé au bestiaire mais absent du catalogue")
        }
    }

    func test_bestiaryOrder_hasNoDuplicates() {
        XCTAssertEqual(EnemyCatalog.bestiaryOrder.count,
                       EnemyCatalog.bestiaryComplete.count,
                       "Doublon dans l'ordre du bestiaire")
    }

    func test_bestiaryOrder_coversEveryCatalogueEnemy() {
        let missing = Set(EnemyCatalog.all.keys)
            .subtracting(EnemyCatalog.bestiaryComplete)
        XCTAssertTrue(missing.isEmpty,
                      "Ennemis du catalogue absents du bestiaire : \(missing.sorted())")
    }

    func test_everyBestiaryEnemyHasLore() {
        for id in EnemyCatalog.bestiaryOrder {
            XCTAssertFalse((EnemyCatalog.lore[id] ?? "").isEmpty,
                           "Paragraphe de bestiaire manquant pour \(id)")
        }
    }
}
