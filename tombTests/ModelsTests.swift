//
//  ModelsTests.swift
//  Sanity-checks sur les enums du domaine — qu'on les considère comme
//  contrat stable (utilisés dans le fichier .ink, dans les saves, dans
//  les achievements). Si quelqu'un renomme un `rawValue` par mégarde,
//  ces tests sautent.
//

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

    func test_Chapter_bannerImageNameConvention() {
        XCTAssertEqual(Chapter.village.bannerImageName, "chapter_village")
        XCTAssertEqual(Chapter.marsh.bannerImageName, "chapter_marsh")
        XCTAssertEqual(Chapter.ending.bannerImageName, "chapter_ending")
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
}
