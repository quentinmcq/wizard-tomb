//
//  ItemCatalog.swift
//  Item catalogue: display name + short description for the inventory sheet.
//

import Foundation

/// Effet déclenché quand le joueur "utilise" un item depuis l'inventaire.
enum ConsumableEffect: Equatable {
    case heal(Int)              // +n Endurance, capé au max
    case restoreLuck            // ramène la Chance à son maximum
    /// Bonus d'Habileté appliqué au prochain jet d'attaque uniquement
    /// (modifie BattleState.playerSkillBonus). Utilisable seulement en
    /// combat, sur `.awaitingAction`.
    case boostSkillNextAttack(Int)
    /// Pénalité d'Habileté pour l'ennemi sur le prochain jet uniquement.
    /// Idem : utilisable seulement en combat.
    case weakenEnemyNextAttack(Int)
}

/// Catégorie d'arme équipable. Pour différencier le bonus appliqué quand
/// elle est portée (le joueur ne tient qu'une seule arme à la fois).
enum WeaponKind: Equatable {
    case sharpened      // +1 Habileté
    case cursed         // +2 Habileté, -1 Chance
    case assassin       // +1 Chance (lame légère, jets de Chance précis)
}

enum ItemCatalog {

    struct Info {
        let name: String
        let description: String
        /// SF Symbol used as the row icon. Themed per object so the inventory
        /// is scannable without reading every line.
        let icon: String
        /// Optional short label shown as a tag under the description. Use it
        /// for items that grant an ongoing or already-applied mechanical
        /// effect ("Affaiblit le spectre", "+1 Habileté permanente"). Nil for
        /// purely narrative / quest tokens.
        let effect: String?
        /// Si non-nil, un bouton "Utiliser" apparaît dans l'inventaire. À
        /// l'usage, l'effet est appliqué et l'item disparaît du sac.
        let consumable: ConsumableEffect?
        /// Si non-nil, l'item peut être équipé en arme principale (un seul
        /// slot). Le bonus n'est appliqué que tant que l'arme est portée.
        let weapon: WeaponKind?
        /// True pour les items dont l'effet a été appliqué immédiatement au
        /// pickup (bénédictions, sang de basilic, etc.). L'inventaire les
        /// garde comme trace du parcours mais affiche un chip « Effet
        /// appliqué » à la place du bouton Utiliser — le joueur sait qu'il
        /// n'y a rien à faire de plus.
        let bonusAppliedAtPickup: Bool

        init(name: String, description: String, icon: String,
             effect: String? = nil,
             consumable: ConsumableEffect? = nil,
             weapon: WeaponKind? = nil,
             bonusAppliedAtPickup: Bool = false) {
            self.name = name
            self.description = description
            self.icon = icon
            self.effect = effect
            self.consumable = consumable
            self.weapon = weapon
            self.bonusAppliedAtPickup = bonusAppliedAtPickup
        }
    }

    static let all: [String: Info] = [
        "bronze_key": Info(
            name: "Clé en bronze",
            description: "Une vieille clé verdie par les siècles, repêchée dans la vase d'un marais. Elle ouvre un passage latéral à l'entrée du tombeau.",
            icon: "bronze_key"
        ),
        "amulet": Info(
            name: "Amulette",
            description: "L'amulette du sorcier Mortimer, dérobée il y a cinquante ans et cachée dans son propre tombeau. Sans elle, ton village est condamné.",
            icon: "moon.stars.fill",
            effect: "Objectif de la quête"
        ),
        "blessing": Info(
            name: "Bénédiction du mendiant",
            description: "Le vieil homme aux yeux trop clairs t'a murmuré quelques mots après avoir empoché ta pièce. Le seuil de ta Chance s'en est trouvé un peu plus haut.",
            icon: "beggar_blessing",
            effect: "+1 Chance permanente",
            bonusAppliedAtPickup: true
        ),
        "healing_potion": Info(
            name: "Potion de soin",
            description: "Fiole de verre épais remplie d'un liquide ambré, bouchée à la cire noire. Une gorgée referme les plaies sans cicatriser les vraies blessures.",
            icon: "green_potion",
            effect: "+4 Endurance à l'usage",
            consumable: .heal(4)
        ),
        "stolen_loot": Info(
            name: "Butin du tombeau",
            description: "Une bourse alourdie de pièces volées au sarcophage d'un seigneur endormi. Maître Aldwin remarquera-t-il l'éclat dans ton regard ?",
            icon: "bag.fill",
            effect: "Modifie la fin de l'aventure"
        ),
        "dead_lord_talisman": Info(
            name: "Talisman du seigneur endormi",
            description: "Petit talisman gris-cendre apparu sur la pierre du sarcophage en remerciement de ton respect. On dit que ces objets brûlent face aux esprits maléfiques.",
            icon: "seal.fill",
            effect: "−1 Habileté au spectre"
        ),
        "rumour_mortimer": Info(
            name: "Rumeur de l'auberge",
            description: "Un voyageur ivre a évoqué un disciple banni de Mortimer, encore vivant dans la forêt. Garde l'œil ouvert au carrefour.",
            icon: "dialogue_option",
            effect: "Débloque un choix dans la forêt"
        ),
        "carrefour_blade_rumour": Info(
            name: "Rumeur des bûcherons",
            description: "Une lame plantée dans le tronc d'un arbre près du carrefour. Personne n'a osé la déloger.",
            icon: "dialogue_option",
            effect: "Débloque une option au carrefour"
        ),
        "seuils_word": Info(
            name: "Le mot du Seuil",
            description: "Un mot gravé profond au-dessus de l'autel du père Cassien, lisible seulement par qui s'arrête trois fois pour le déchiffrer. Il pèse dans ta bouche comme une pierre tiède.",
            icon: "spellbook",
            effect: "Indice caché — usage inconnu"
        ),
        "protective_charm": Info(
            name: "Charme du sage",
            description: "Petit objet d'os noué de fil rouge, glissé dans ta poche par le vieux sage de la forêt. On dit qu'il repousse la peur insufflée par les esprits hostiles.",
            icon: "shield.lefthalf.filled",
            effect: "−1 Habileté au spectre"
        ),
        "spirit_blood": Info(
            name: "Sang spectral",
            description: "Tu as bu au calice de l'Esprit Vengeur. La chaleur cuivrée court encore dans tes veines. La légende veut qu'elle protège contre les âmes prisonnières.",
            icon: "first_blood",
            effect: "−1 Habileté au spectre"
        ),
        "sharpened_blade": Info(
            name: "Épée aiguisée",
            description: "Maître Borvic a frappé ta lame sept fois sur l'enclume. Elle tranche maintenant comme une chose qui sait à quoi elle sert.",
            icon: "sword",
            effect: "Arme — +1 Habileté tant qu'équipée",
            weapon: .sharpened
        ),
        "forgotten_grimoire": Info(
            name: "Grimoire des oubliés",
            description: "Un livre relié de cuir bordeaux ramassé dans une crypte. Quand tu l'ouvres, tu sens des idées plus rapides — sans pouvoir dire si c'est l'effet du livre ou ton propre soulagement d'être sorti vivant.",
            icon: "spellbook",
            effect: "Lore — compagnon de quête"
        ),
        "widow_token": Info(
            name: "Médaillon de la veuve",
            description: "Petit médaillon de fer noirci confié par une vieille femme du village. Son fils Tomas est descendu dans le tombeau il y a quinze ans. Il portait une chaîne d'argent.",
            icon: "life",
            effect: "Quête secondaire en cours"
        ),
        "silver_chain": Info(
            name: "Chaîne d'argent de Tomas",
            description: "Tu l'as décrochée du cou d'un squelette dans le couloir du tombeau. Une vieille femme l'attend, quelque part à Roncebrune.",
            icon: "silver_necklace",
            effect: "+30 au score si rapporté"
        ),

        // ----- Forêt (chap. II) -----

        "forest_herbs": Info(
            name: "Herbes forestières",
            description: "Une poignée d'achillée et de millepertuis ramassée près des pierres dressées. Mâchées et avalées, elles ralentissent le sang qui coule.",
            icon: "forest_grass",
            effect: "+2 Endurance à l'usage",
            consumable: .heal(2)
        ),
        "hunter_compass": Info(
            name: "Boussole du chasseur",
            description: "Une rose des vents sculptée dans du chêne, taillée par un voyageur reconnaissant. Elle s'oriente toute seule, même dans la brume la plus opaque.",
            icon: "compass",
            effect: "Aide à s'orienter dans les passages obscurs"
        ),
        "assassin_dagger": Info(
            name: "Lame du chasseur Brann",
            description: "Une dague courte, soigneusement huilée, retrouvée dans la cache d'une cabane abandonnée. Brann la maniait quand il pouvait encore — légère, précise, faite pour trouver l'angle mort.",
            icon: "dagger",
            effect: "Arme — +1 Chance tant qu'équipée",
            weapon: .assassin
        ),
        "tomb_map": Info(
            name: "Plan grossier du tombeau",
            description: "Un parchemin trouvé dans une vieille tour de guet. Quelqu'un a tenté de cartographier les couloirs sous les ruines, à l'encre sépia, avec des ☥ marquant les pièges.",
            icon: "map.fill",
            effect: "+1 Chance permanente"
        ),
        "holy_water": Info(
            name: "Eau bénite",
            description: "Une petite fiole bouchée de cire noire, gravée d'une croix simple. L'eau à l'intérieur ne s'est pas troublée malgré les années — Mortimer y a mis trop d'efforts à la chercher pour qu'elle soit ordinaire.",
            icon: "holy_water",
            effect: "−1 Habileté au spectre"
        ),

        // ----- Donjon (chap. V) -----

        "runic_key": Info(
            name: "Rune-clé d'argile",
            description: "Une petite tablette d'argile gravée de trois signes concentriques. Mortimer l'a faite pour ouvrir une porte qu'il voulait scellée à tous les autres.",
            icon: "clay_rune",
            effect: "Ouvre la chambre des runes"
        ),
        "tarnished_mirror": Info(
            name: "Miroir terni",
            description: "Un petit miroir d'argent rouillé, cerclé d'écailles, repêché sur une plateforme inondée. Sa surface ne reflète plus rien clairement — mais elle reflète encore *quelque chose*.",
            icon: "silver_miror",
            effect: "Permet d'affronter le basilic"
        ),
        "basilisk_blood": Info(
            name: "Sang de basilic",
            description: "Liquide épais et tiède, ramassé dans la dépouille du basilic du tombeau. La légende prétend qu'il rend la vue plus claire que la lumière du jour — tu vois maintenant les ouvertures que les autres manquent.",
            icon: "basilic_blood",
            effect: "+1 Chance permanente",
            bonusAppliedAtPickup: true
        ),

        // ----- Roncebrune élargi -----

        "priest_blessing": Info(
            name: "Bénédiction du père Cassien",
            description: "Le vieux prêtre du temple de Roncebrune a posé ses mains sur ton front et murmuré une prière qu'il portait depuis cinquante ans. Il avait connu Mortimer enfant — il aurait préféré que tu n'aies jamais à descendre dans son trou.",
            icon: "father_blessing",
            effect: "+1 Endurance max et +1 Chance permanente",
            bonusAppliedAtPickup: true
        ),
        "hardened_skin": Info(
            name: "Peau durcie",
            description: "Mère Esmé t'a vendu une fiole rouge. Tu l'as bue cul sec. Ta peau a la consistance et la couleur du cuir tanné — c'est peu confortable, mais ça encaisse mieux.",
            icon: "red_potion",
            effect: "+2 Endurance max",
            bonusAppliedAtPickup: true
        ),
        "necro_oil": Info(
            name: "Huile noire de mère Esmé",
            description: "Petite fiole d'un liquide visqueux qui sent la cire de cathédrale. Une goutte sur le sol et les morts qui marchent encore hésitent à approcher.",
            icon: "black_potion",
            effect: "Combat — affaiblit l'ennemi (−3 Habileté pour un round)",
            consumable: .weakenEnemyNextAttack(3)
        ),
        "witch_fetish": Info(
            name: "Fétiche de la sorcière",
            description: "Petit fagot d'os de poisson cousu d'un fil de cheveux blancs, échangé contre trois gouttes de ton sang. À écraser quand tu sens un regard dans ton dos.",
            icon: "witch_bone",
            effect: "Combat — +2 Habileté pour un round",
            consumable: .boostSkillNextAttack(2)
        ),
        "witch_brew": Info(
            name: "Goût de la sorcière",
            description: "Dé à coudre d'un liquide brun et sucré que tu as bu sans demander. Le monde s'est réorganisé. Tu vois les angles un peu mieux.",
            icon: "wand.and.stars",
            effect: "+1 Habileté permanente"
        ),

        // ----- Forêt profonde -----

        "cursed_blade": Info(
            name: "Lame trempée chez la sorcière",
            description: "Ton épée est ressortie noire de la marmite de la hutte. Elle coupe l'air d'un sifflement sec. Quelque chose en toi s'est éteint en échange.",
            icon: "bolt.fill",
            effect: "Arme — +2 Habileté, −1 Chance tant qu'équipée",
            weapon: .cursed
        ),
        "boar_meat": Info(
            name: "Hure de sanglier titanesque",
            description: "Tu as détaché un morceau de viande sombre du sanglier que tu as terrassé. Ça pèse, ça sent fort, mais ça nourrit comme rien d'autre.",
            icon: "fork.knife",
            effect: "+3 Endurance à l'usage",
            consumable: .heal(3)
        ),
        "lycan_pendant": Info(
            name: "Pendentif d'argent du lycanthrope",
            description: "Collier détaché du cou d'un loup-garou abattu. Le croissant gravé t'a brûlé légèrement la paume quand tu l'as ramassé. Tu sens qu'il reconnaît la lune.",
            icon: "amulet",
            effect: "+2 Endurance maximum",
            bonusAppliedAtPickup: true
        ),

        // ----- Aile sud du tombeau -----

        "pit_signet": Info(
            name: "Bague de fer noire",
            description: "Glissée sous une côte effritée dans la fosse aux squelettes. Le sceau gravé n'appartient à aucune lignée connue — il porte une chaleur sourde, comme si quelqu'un tenait ta main d'en bas.",
            icon: "circle.fill",
            effect: "+1 Chance permanente",
            bonusAppliedAtPickup: true
        ),
        "silver_seal_ring": Info(
            name: "Anneau au sceau étoilé",
            description: "Anneau d'argent gravé d'une étoile à six pointes, trouvé dans un sarcophage anonyme du caveau des seigneurs. Quelqu'un a effacé tous les noms autour, mais pas le sceau.",
            icon: "star.fill",
            effect: "+1 Habileté permanente",
            bonusAppliedAtPickup: true
        ),
        "mortimer_attention": Info(
            name: "L'attention de Mortimer",
            description: "Pas un objet à proprement parler — plutôt une chaleur entre tes omoplates depuis que tu as répondu à la voix dans la chambre. Le spectre sait qui tu es. C'est un avantage : tu n'as plus peur de lui.",
            icon: "eye.trianglebadge.exclamationmark.fill",
            effect: "Le spectre a perdu sa surprise"
        )
    ]

    /// Returns the info for an id, with a sensible fallback if the item is
    /// not catalogued.
    static func info(_ id: String) -> Info {
        if let info = all[id] { return info }
        let prettyName = id
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return Info(name: prettyName, description: "", icon: "sparkles")
    }
}
