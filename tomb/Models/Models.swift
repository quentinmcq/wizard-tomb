import Foundation

// MARK: - Player state

struct PlayerState: Codable {
    var skill: Int
    var skillMax: Int
    var stamina: Int
    var staminaMax: Int
    var luck: Int
    var luckMax: Int
    var gold: Int = 10
    var items: Set<String> = []
    var equippedWeapon: String? = nil

    var isDead: Bool { stamina <= 0 }

    static func rolled() -> PlayerState {
        let skill   = Int.random(in: 1...6) + 6
        let stamina = Int.random(in: 1...6) + Int.random(in: 1...6) + 12
        let luck    = Int.random(in: 1...6) + 6
        return PlayerState(
            skill: skill, skillMax: skill,
            stamina: stamina, staminaMax: stamina,
            luck: luck, luckMax: luck
        )
    }

    func canEquip(_ weapon: WeaponKind) -> Bool {
        let d = weapon.delta
        return skillMax + d.skill >= 1
            && luckMax + d.luck >= 1
            && skill + d.skill >= 1
            && luck + d.luck >= 0
    }

    /// Applique (`sign = +1`) ou retire (`sign = −1`) le bonus d'une arme.
    ///
    /// ⚠️ Volontairement sans clamp. L'implémentation précédente terminait
    /// par `luck = max(1, luck)` : équiper la lame maudite avec 1 en Chance
    /// donnait `max(1, 0) = 1` — le malus était absorbé par le plancher —
    /// puis la retirer rendait `1 + 1 = 2`. Chaque cycle équiper/déséquiper
    /// offrait ainsi +1 Chance permanente, indéfiniment répétable dès que
    /// la Chance retombait au plancher. La validité des valeurs est
    /// désormais garantie en amont par `canEquip(_:)`, ce qui rend
    /// l'aller-retour strictement neutre.
    mutating func applyWeaponBonus(_ weapon: WeaponKind, sign: Int) {
        let d = weapon.delta
        skill    += d.skill * sign
        skillMax += d.skill * sign
        luck     += d.luck * sign
        luckMax  += d.luck * sign
    }

    mutating func testLuck(roll: Int? = nil) -> (lucky: Bool, roll: Int, threshold: Int) {
        let r = roll ?? (Int.random(in: 1...6) + Int.random(in: 1...6))
        let threshold = luck
        let lucky = r <= luck
        luck -= 1
        return (lucky, r, threshold)
    }
}

// MARK: - Choice offered to the player (fed by Ink options)

struct Choice: Identifiable, Codable {
    let id: Int
    let text: String
    let isSpecial: Bool
    let priceGold: Int?

    init(id: Int, text: String,
         isSpecial: Bool = false,
         priceGold: Int? = nil) {
        self.id = id
        self.text = text
        self.isSpecial = isSpecial
        self.priceGold = priceGold
    }

    enum CodingKeys: String, CodingKey { case id, text, isSpecial, priceGold }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.isSpecial = try c.decodeIfPresent(Bool.self, forKey: .isSpecial) ?? false
        self.priceGold = try c.decodeIfPresent(Int.self, forKey: .priceGold)
    }
}

// MARK: - Margin event messages

struct EventMessage: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case gain
        case heal
        case damage
        case loss
        case lucky
        case unlucky
        case info
    }

    let id: UUID
    let text: String
    let kind: Kind
    let iconOverride: String?

    init(text: String, kind: Kind, iconOverride: String? = nil) {
        self.id = UUID()
        self.text = text
        self.kind = kind
        self.iconOverride = iconOverride
    }

    enum CodingKeys: String, CodingKey { case id, text, kind, iconOverride }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.iconOverride = try c.decodeIfPresent(String.self, forKey: .iconOverride)
    }
}

// MARK: - Enemy

struct Enemy: Equatable {
    let id: String
    let name: String
    let subtitle: String?
    var skill: Int
    var stamina: Int
    let staminaMax: Int
    let damageBonus: Int
    let abilityNote: String?

    init(id: String, name: String, subtitle: String? = nil,
         skill: Int, stamina: Int,
         damageBonus: Int = 0, abilityNote: String? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.skill = skill
        self.stamina = stamina
        self.staminaMax = stamina
        self.damageBonus = damageBonus
        self.abilityNote = abilityNote
    }
}

// MARK: - Combat configuration attached to a passage

struct BattleSetup {
    let enemy: Enemy
    let fleeTarget: String?

    init(enemy: Enemy, fleeTarget: String? = nil) {
        self.enemy = enemy
        self.fleeTarget = fleeTarget
    }
}

// MARK: - Jet de Chance narratif

struct NarrativeLuckRoll: Identifiable, Equatable {
    let id = UUID()
    let dice: (Int, Int)
    let threshold: Int
    let lucky: Bool

    static func == (lhs: NarrativeLuckRoll, rhs: NarrativeLuckRoll) -> Bool {
        lhs.id == rhs.id
    }
}

enum LuckPromptKind: String, Equatable {
    case generic
    case book
    case amulette

    var buttonLabel: String {
        switch self {
        case .generic:  return "Tenter ma chance"
        case .book:     return "Lire la première phrase"
        case .amulette: return "Tendre la main vers l'amulette"
        }
    }
}

// MARK: - Issue finale de l'aventure

enum FinalOutcome: String, Codable, CaseIterable {
    case honour
    case destruction
    case dark
    case transcendence
    case death

    var title: String {
        switch self {
        case .honour:        return "La voie de l'honneur"
        case .destruction:   return "Le sortilège brisé"
        case .dark:          return "L'ombre qui s'allonge"
        case .transcendence: return "Le passage du sage"
        case .death:         return "Une épitaphe oubliée"
        }
    }

    var blurb: String {
        switch self {
        case .honour:        return "Tu as rapporté l'amulette à Aldwin. Le village respire."
        case .destruction:   return "Tu as brisé l'amulette aux pieds d'Aldwin. Mortimer s'éteint pour de bon."
        case .dark:          return "Tu as quitté Roncebrune avec l'amulette. Quelque part, une ombre nouvelle s'allonge."
        case .transcendence: return "Tu as scellé Mortimer par les trois forces et offert l'amulette au ciel."
        case .death:         return "La pierre froide du tombeau a accueilli ton dos."
        }
    }

    var hint: String {
        switch self {
        case .honour:        return "Rends ce qu'on t'a confié."
        case .destruction:   return "Le sage de la forêt savait. Brise ce qui retient."
        case .dark:          return "Ce qui brille n'appartient plus à personne."
        case .transcendence: return "Trois protections, trois forces — apporte-les toutes."
        case .death:         return "Le tombeau finit par avaler ceux qui le sous-estiment."
        }
    }
}

// MARK: - Difficulté

enum Difficulty: String, Codable, CaseIterable {
    case adventurer
    case veteran
    case legend

    var title: String {
        switch self {
        case .adventurer: return "Aventurier"
        case .veteran:    return "Vétéran"
        case .legend:     return "Légende"
        }
    }

    var blurb: String {
        switch self {
        case .adventurer: return "Tirage classique. Recommandé pour une première aventure."
        case .veteran:    return "Tu perds 1 point sur chacune de tes statistiques de départ."
        case .legend:     return "Tu perds 1 point sur chacune de tes stats. Les ennemis gagnent +1 Habileté."
        }
    }

    var statPenalty: Int {
        switch self {
        case .adventurer: return 0
        case .veteran:    return -1
        case .legend:     return -1
        }
    }

    var enemySkillBonus: Int {
        switch self {
        case .adventurer, .veteran: return 0
        case .legend:               return 1
        }
    }

    var scoreMultiplier: Double {
        switch self {
        case .adventurer: return 1.0
        case .veteran:    return 1.25
        case .legend:     return 1.5
        }
    }
}

// MARK: - Chapitres narratifs

enum Chapter: String, Codable, CaseIterable {
    case village
    case forest
    case marsh
    case ruins
    case tomb
    case chamber
    case homecoming
    case ending

    var title: String {
        switch self {
        case .village:    return "Chapitre I — Le village"
        case .forest:     return "Chapitre II — La forêt"
        case .marsh:      return "Chapitre III — Le marais"
        case .ruins:      return "Chapitre IV — Les ruines"
        case .tomb:       return "Chapitre V — Le tombeau"
        case .chamber:    return "Chapitre VI — La chambre voûtée"
        case .homecoming: return "Chapitre VII — Le retour"
        case .ending:     return "Épilogue"
        }
    }

    var shortTitle: String {
        switch self {
        case .village:    return "Le village"
        case .forest:     return "La forêt"
        case .marsh:      return "Le marais"
        case .ruins:      return "Les ruines"
        case .tomb:       return "Le tombeau"
        case .chamber:    return "La chambre voûtée"
        case .homecoming: return "Le retour"
        case .ending:     return "Épilogue"
        }
    }
}

// MARK: - Character roll (intro stat draw)

struct CharacterRoll: Equatable {
    let skillDie: Int
    let staminaDice: (Int, Int)
    let luckDie: Int
    let difficulty: Difficulty

    var skillBonus: Int   { 6 + difficulty.statPenalty }
    var staminaBonus: Int { 12 + difficulty.statPenalty }
    var luckBonus: Int    { 6 + difficulty.statPenalty }

    var skill: Int   { max(1, skillDie + skillBonus) }
    var stamina: Int { max(1, staminaDice.0 + staminaDice.1 + staminaBonus) }
    var luck: Int    { max(1, luckDie + luckBonus) }

    var player: PlayerState {
        PlayerState(
            skill: skill,     skillMax: skill,
            stamina: stamina, staminaMax: stamina,
            luck: luck,       luckMax: luck
        )
    }

    static func rolled(difficulty: Difficulty) -> CharacterRoll {
        CharacterRoll(
            skillDie: Int.random(in: 1...6),
            staminaDice: (Int.random(in: 1...6), Int.random(in: 1...6)),
            luckDie: Int.random(in: 1...6),
            difficulty: difficulty
        )
    }

    static func == (lhs: CharacterRoll, rhs: CharacterRoll) -> Bool {
        lhs.skillDie == rhs.skillDie
            && lhs.staminaDice == rhs.staminaDice
            && lhs.luckDie == rhs.luckDie
            && lhs.difficulty == rhs.difficulty
    }
}

// MARK: - Dice

func roll2d6() -> Int {
    Int.random(in: 1...6) + Int.random(in: 1...6)
}
