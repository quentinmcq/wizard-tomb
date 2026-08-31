import XCTest
@testable import tomb

// ⚠️ Les sauvegardes sont décodées telles quelles au lancement : un champ
// ajouté sans `decodeIfPresent` casse silencieusement les parties en cours.
final class PersistenceTests: XCTestCase {
    // MARK: - PlayerState

    func test_playerState_roundTripsThroughJSON() throws {
        var original = PlayerState(
            skill: 11, skillMax: 12,
            stamina: 17, staminaMax: 22,
            luck: 6, luckMax: 9
        )
        original.gold = 34
        original.items = ["amulet", "silver_chain", "cursed_blade"]
        original.equippedWeapon = "cursed_blade"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlayerState.self, from: data)

        XCTAssertEqual(decoded.skill, 11)
        XCTAssertEqual(decoded.skillMax, 12)
        XCTAssertEqual(decoded.stamina, 17)
        XCTAssertEqual(decoded.staminaMax, 22)
        XCTAssertEqual(decoded.luck, 6)
        XCTAssertEqual(decoded.luckMax, 9)
        XCTAssertEqual(decoded.gold, 34)
        XCTAssertEqual(decoded.items, original.items)
        XCTAssertEqual(decoded.equippedWeapon, "cursed_blade")
    }

    // MARK: - Compatibilité ascendante

    func test_choice_decodesLegacyPayloadWithoutOptionalFields() throws {
        let legacy = Data(#"{"id":2,"text":"Entrer dans le tombeau"}"#.utf8)
        let choice = try JSONDecoder().decode(Choice.self, from: legacy)

        XCTAssertEqual(choice.id, 2)
        XCTAssertEqual(choice.text, "Entrer dans le tombeau")
        XCTAssertFalse(choice.isSpecial)
        XCTAssertNil(choice.priceGold)
    }

    func test_choice_decodesCurrentPayload() throws {
        let current = Data(#"{"id":0,"text":"Payer","isSpecial":true,"priceGold":5}"#.utf8)
        let choice = try JSONDecoder().decode(Choice.self, from: current)

        XCTAssertTrue(choice.isSpecial)
        XCTAssertEqual(choice.priceGold, 5)
    }

    func test_eventMessage_decodesLegacyPayloadWithoutIconOverride() throws {
        let id = UUID().uuidString
        let legacy = Data(#"{"id":"\#(id)","text":"Tu perds 2 Endurance.","kind":"damage"}"#.utf8)
        let message = try JSONDecoder().decode(EventMessage.self, from: legacy)

        XCTAssertEqual(message.kind, .damage)
        XCTAssertNil(message.iconOverride)
    }

    // MARK: - Contrats de rawValue

    func test_difficultyRawValues_areStableForSaves() {
        XCTAssertEqual(Difficulty.adventurer.rawValue, "adventurer")
        XCTAssertEqual(Difficulty.veteran.rawValue, "veteran")
        XCTAssertEqual(Difficulty.legend.rawValue, "legend")
    }

    func test_eventMessageKindRawValues_areStableForSaves() {
        XCTAssertEqual(EventMessage.Kind.gain.rawValue, "gain")
        XCTAssertEqual(EventMessage.Kind.heal.rawValue, "heal")
        XCTAssertEqual(EventMessage.Kind.damage.rawValue, "damage")
        XCTAssertEqual(EventMessage.Kind.loss.rawValue, "loss")
        XCTAssertEqual(EventMessage.Kind.lucky.rawValue, "lucky")
        XCTAssertEqual(EventMessage.Kind.unlucky.rawValue, "unlucky")
        XCTAssertEqual(EventMessage.Kind.info.rawValue, "info")
    }
}
