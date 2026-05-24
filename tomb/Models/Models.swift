//
//  Models.swift
//  Data models for the adventure.
//

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
    /// Arme actuellement portée (id d'item dans `ItemCatalog`, doit avoir un
    /// `weapon` non-nil). Le bonus de cette arme est appliqué sur les stats
    /// `skill` / `luck` tant qu'elle est équipée ; le retirer remet les
    /// stats à leur valeur de base. Nil = combat à mains nues / sans arme.
    var equippedWeapon: String? = nil

    var isDead: Bool { stamina <= 0 }

    /// Rolls starting stats as in the original Fighting Fantasy gamebooks.
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

    /// Tests Luck. Returns (lucky, dice roll, luck threshold before the test).
    /// If `roll` is provided, it overrides the random draw (useful to pre-roll
    /// the dice for animation and inject the result afterwards).
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
    /// Index of this choice in `story.options`. Also serves as SwiftUI identity.
    let id: Int
    let text: String
    /// Whether this choice is a notable / conditional one (unlocked by an
    /// item, hidden path, moral fork). Driven by an Ink tag `# special` on
    /// the choice. Affects styling so the player notices it.
    let isSpecial: Bool
    /// Coût en pièces d'or de l'option (encodé dans le .ink via le marker
    /// trailing `[$N]`, ex. `[Payer 5 pièces [$5]]`). `nil` = option non
    /// payante. Quand le joueur n'a pas assez, l'option reste visible mais
    /// est rendue grisée et non cliquable côté UI.
    let priceGold: Int?

    init(id: Int, text: String,
         isSpecial: Bool = false,
         priceGold: Int? = nil) {
        self.id = id
        self.text = text
        self.isSpecial = isSpecial
        self.priceGold = priceGold
    }

    // Manual Codable so older saves (without isSpecial / priceGold) still decode.
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

/// Margin note produced when an Ink effect tag fires or the player acts.
/// `kind` drives the icon and colour in `MarginNote`.
struct EventMessage: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case gain      // item picked up, blessing received
        case heal      // healing
        case damage    // stamina loss
        case loss      // gold spent, resource consumed
        case lucky     // luck test passed
        case unlucky   // luck test failed
        case info      // neutral
    }

    let id: UUID
    let text: String
    let kind: Kind
    /// Override de l'icône asset (ex. `get_items`, `coin`, `gain_luck`,
    /// `gain_life`) quand on veut une marge plus parlante que le pictogramme
    /// dérivé de `kind`. Nil = on retombe sur la table par `kind` dans
    /// `MarginNote`. Optionnel et `decodeIfPresent` côté Codable pour rester
    /// compatible avec les saves antérieures à cette feature.
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
    /// Identifiant catalog (slug). Sert aussi de nom de fichier pour le
    /// portrait dans `tomb/Images/<id>.jpg`.
    let id: String
    let name: String
    /// Sous-titre poétique façon Fighting Fantasy (« Le rôdeur silencieux »,
    /// « La voix patiente »…). Affiché en italique sous le nom dans la
    /// carte de combat et le bestiaire. Nil = pas de sous-titre.
    let subtitle: String?
    /// `var` so passive bonuses (player items, e.g. protective charm vs the
    /// spectre) can adjust the enemy's Skill at combat setup time.
    var skill: Int
    var stamina: Int
    let staminaMax: Int
    /// Bonus de dégâts ajouté à chaque coup encaissé par le joueur. Sert à
    /// donner une « aptitude » aux ennemis (griffes acérées du lycanthrope,
    /// poigne de pierre du gardien…). 0 = ennemi standard (2 dégâts/coup).
    let damageBonus: Int
    /// Phrase courte décrivant l'aptitude, affichée sous la fiche d'ennemi
    /// dans la carte de combat. Nil = pas d'aptitude particulière.
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
    /// If set, a "Flee" button is offered during combat and leads to that knot.
    let fleeTarget: String?

    init(enemy: Enemy, fleeTarget: String? = nil) {
        self.enemy = enemy
        self.fleeTarget = fleeTarget
    }
}

// MARK: - Jet de Chance narratif

/// Snapshot d'un test de Chance déclenché par l'aventure (hors combat) —
/// pièges, lecture du grimoire, tentative de saisir l'amulette. Affiché
/// en overlay central par `NarrativeLuckOverlay`.
struct NarrativeLuckRoll: Identifiable, Equatable {
    let id = UUID()
    let dice: (Int, Int)
    let threshold: Int
    let lucky: Bool

    static func == (lhs: NarrativeLuckRoll, rhs: NarrativeLuckRoll) -> Bool {
        lhs.id == rhs.id
    }
}

/// Catégorie d'un jet de Chance narratif en attente d'un clic du joueur.
/// Drive le libellé du bouton "Tenter ma chance" et l'effet narratif
/// associé (l'effet mécanique est appliqué côté `applyEffectTags`).
enum LuckPromptKind: String, Equatable {
    case generic   // # luck_test : piège, esquive, etc.
    case book      // # luck_test_book : lire le grimoire
    case amulette  // # luck_grab_amulette : saisir l'amulette face à Mortimer

    /// Libellé affiché sur le bouton de déclenchement.
    var buttonLabel: String {
        switch self {
        case .generic:  return "Tenter ma chance"
        case .book:     return "Lire la première phrase"
        case .amulette: return "Tendre la main vers l'amulette"
        }
    }
}

// MARK: - Issue finale de l'aventure

/// Identifié par le tag `# outcome: <kind>` posé sur chaque knot de fin.
/// Sert au calcul du score et à l'affichage d'un grade thématique.
enum FinalOutcome: String, Codable, CaseIterable {
    case honour         // fin_honneur
    case destruction    // fin_destruction
    case dark           // fin_sombre
    case transcendence  // fin_transcendance
    case death          // mort

    /// Libellé affiché dans l'écran « Tes aventures ».
    var title: String {
        switch self {
        case .honour:        return "La voie de l'honneur"
        case .destruction:   return "Le sortilège brisé"
        case .dark:          return "L'ombre qui s'allonge"
        case .transcendence: return "Le passage du sage"
        case .death:         return "Une épitaphe oubliée"
        }
    }

    /// Court résumé (montré sous le titre une fois la fin découverte).
    var blurb: String {
        switch self {
        case .honour:        return "Tu as rapporté l'amulette à Aldwin. Le village respire."
        case .destruction:   return "Tu as brisé l'amulette aux pieds d'Aldwin. Mortimer s'éteint pour de bon."
        case .dark:          return "Tu as quitté Roncebrune avec l'amulette. Quelque part, une ombre nouvelle s'allonge."
        case .transcendence: return "Tu as scellé Mortimer par les trois forces et offert l'amulette au ciel."
        case .death:         return "La pierre froide du tombeau a accueilli ton dos."
        }
    }

    /// Indice montré quand la fin n'a pas encore été atteinte. Léger spoiler-
    /// free : juste un teaser pour pousser à explorer.
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
    case adventurer  // normal
    case veteran     // stats de départ -1, score x1.25
    case legend      // stats de départ -1, ennemis +1 Habileté, score x1.5

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

    /// Modificateur appliqué à chaque stat tirée (Habileté, Endurance, Chance).
    /// Légende reste à -1 (au lieu de -2 jusqu'ici) : la pénalité cumulée
    /// avec `enemySkillBonus = +1` aboutissait à un écart effectif de -3 vs
    /// Aventurier, ce qui rendait les boss limite-injouables même avec un
    /// run optimisé. À -1, l'écart effectif reste à -2 — sévère mais fair.
    var statPenalty: Int {
        switch self {
        case .adventurer: return 0
        case .veteran:    return -1
        case .legend:     return -1
        }
    }

    /// Bonus d'Habileté ajouté à chaque ennemi avant combat.
    var enemySkillBonus: Int {
        switch self {
        case .adventurer, .veteran: return 0
        case .legend:               return 1
        }
    }

    /// Multiplicateur de score final.
    var scoreMultiplier: Double {
        switch self {
        case .adventurer: return 1.0
        case .veteran:    return 1.25
        case .legend:     return 1.5
        }
    }
}

// MARK: - Chapitres narratifs

/// Découpage de l'aventure en chapitres. Set côté Ink via le tag
/// `# chapter: <id>` et affiché en haut de la page pour donner au joueur
/// un repère narratif sans révéler la structure.
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

    /// Variante courte pour les emplacements contraints (chip du HUD,
    /// fil d'Ariane). Sans la numérotation romaine ni le mot « Chapitre ».
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

    /// Nom de la gravure de paysage embarquée pour ce chapitre.
    /// Convention : `chapter_<rawValue>.jpg` dans `tomb/Images/`.
    var bannerImageName: String { "chapter_\(rawValue)" }
}

// MARK: - Character roll (intro stat draw)

/// Keeps the individual dice that determined the starting stats, so we can
/// animate them in the character creation screen and rebuild a `PlayerState`
/// from them.
struct CharacterRoll: Equatable {
    let skillDie: Int          // 1d6
    let staminaDice: (Int, Int) // 2d6
    let luckDie: Int           // 1d6
    let difficulty: Difficulty

    // Bonus de base atténué par la difficulté.
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

/// Small helper for combat rolls (2d6).
func roll2d6() -> Int {
    Int.random(in: 1...6) + Int.random(in: 1...6)
}
