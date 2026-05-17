//
//  ItemCatalog.swift
//  Item catalogue: display name + short description for the inventory sheet.
//

import Foundation

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

        init(name: String, description: String, icon: String, effect: String? = nil) {
            self.name = name
            self.description = description
            self.icon = icon
            self.effect = effect
        }
    }

    static let all: [String: Info] = [
        "bronze_key": Info(
            name: "Clé en bronze",
            description: "Une vieille clé verdie par les siècles, repêchée dans la vase d'un marais. Elle ouvre un passage latéral à l'entrée du tombeau.",
            icon: "key.fill"
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
            icon: "hands.sparkles.fill",
            effect: "+1 Chance permanente"
        ),
        "healing_potion": Info(
            name: "Potion de soin",
            description: "Fiole de verre épais remplie d'un liquide ambré, trouvée sur un gobelin éclaireur. Tu en as déjà bu une gorgée.",
            icon: "cross.vial.fill",
            effect: "+6 Endurance déjà appliqué"
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
            icon: "text.bubble.fill",
            effect: "Débloque un choix dans la forêt"
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
            icon: "drop.fill",
            effect: "−1 Habileté au spectre"
        ),
        "sharpened_blade": Info(
            name: "Épée aiguisée",
            description: "Maître Borvic a frappé ta lame sept fois sur l'enclume. Elle tranche maintenant comme une chose qui sait à quoi elle sert.",
            icon: "bolt.fill",
            effect: "+1 Habileté permanente"
        ),
        "forgotten_grimoire": Info(
            name: "Grimoire des oubliés",
            description: "Un livre relié de cuir bordeaux ramassé dans une crypte. Quand tu l'ouvres, quelque chose se débloque en toi, comme une porte que tu n'avais jamais remarquée.",
            icon: "book.closed.fill",
            effect: "+1 Chance permanente"
        ),
        "widow_token": Info(
            name: "Médaillon de la veuve",
            description: "Petit médaillon de fer noirci confié par une vieille femme du village. Son fils Tomas est descendu dans le tombeau il y a quinze ans. Il portait une chaîne d'argent.",
            icon: "heart.fill",
            effect: "Quête secondaire en cours"
        ),
        "silver_chain": Info(
            name: "Chaîne d'argent de Tomas",
            description: "Tu l'as décrochée du cou d'un squelette dans le couloir du tombeau. Une vieille femme l'attend, quelque part à Roncebrune.",
            icon: "link",
            effect: "+30 au score si rapporté"
        ),

        // ----- Forêt (chap. II) -----

        "forest_herbs": Info(
            name: "Herbes forestières",
            description: "Une poignée d'achillée et de millepertuis ramassée près des pierres dressées. Quand on les broie, elles ralentissent le sang qui coule.",
            icon: "leaf.fill",
            effect: "+3 Endurance déjà appliqué"
        ),
        "hunter_compass": Info(
            name: "Boussole du chasseur",
            description: "Une rose des vents sculptée dans du chêne, taillée par un voyageur reconnaissant. Elle s'oriente toute seule, même dans la brume la plus opaque.",
            icon: "location.north.fill",
            effect: "Aide à s'orienter dans les passages obscurs"
        ),
        "assassin_dagger": Info(
            name: "Lame du chasseur Brann",
            description: "Une dague courte, soigneusement huilée, retrouvée dans la cache d'une cabane abandonnée. Brann la maniait quand il pouvait encore.",
            icon: "scissors",
            effect: "+1 Habileté permanente"
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
            icon: "drop.halffull",
            effect: "−1 Habileté au spectre"
        ),

        // ----- Donjon (chap. V) -----

        "runic_key": Info(
            name: "Rune-clé d'argile",
            description: "Une petite tablette d'argile gravée de trois signes concentriques. Mortimer l'a faite pour ouvrir une porte qu'il voulait scellée à tous les autres.",
            icon: "key.viewfinder",
            effect: "Ouvre la chambre des runes"
        ),
        "tarnished_mirror": Info(
            name: "Miroir terni",
            description: "Un petit miroir d'argent rouillé, cerclé d'écailles, repêché sur une plateforme inondée. Sa surface ne reflète plus rien clairement — mais elle reflète encore *quelque chose*.",
            icon: "circle.hexagongrid.fill",
            effect: "Permet d'affronter le basilic"
        ),
        "basilisk_blood": Info(
            name: "Sang de basilic",
            description: "Liquide épais et tiède, ramassé dans la dépouille du basilic du tombeau. La légende prétend qu'il rend la vue plus claire que la lumière du jour.",
            icon: "eye.fill",
            effect: "+1 Habileté permanente"
        ),

        // ----- Roncebrune élargi -----

        "priest_blessing": Info(
            name: "Bénédiction du père Cassien",
            description: "Le vieux prêtre du temple de Roncebrune a posé ses mains sur ton front et murmuré une prière qu'il portait depuis cinquante ans. Il avait connu Mortimer enfant — il aurait préféré que tu n'aies jamais à descendre dans son trou.",
            icon: "cross.fill",
            effect: "+1 Endurance max et +1 Chance permanente"
        ),
        "hardened_skin": Info(
            name: "Peau durcie",
            description: "Mère Esmé t'a vendu une fiole rouge. Tu l'as bue cul sec. Ta peau a la consistance et la couleur du cuir tanné — c'est peu confortable, mais ça encaisse mieux.",
            icon: "shield.fill",
            effect: "Endurance temporairement renforcée"
        ),
        "necro_oil": Info(
            name: "Huile noire de mère Esmé",
            description: "Petite fiole d'un liquide visqueux qui sent la cire de cathédrale. Une goutte sur le sol et les morts qui marchent encore hésitent à approcher.",
            icon: "drop.fill",
            effect: "Repousse les morts-vivants"
        ),
        "witch_fetish": Info(
            name: "Fétiche de la sorcière",
            description: "Petit fagot d'os de poisson cousu d'un fil de cheveux blancs, échangé contre trois gouttes de ton sang. À écraser quand tu sens un regard dans ton dos.",
            icon: "moon.zzz.fill",
            effect: "Don ambigu — la sorcière en tirera quelque chose"
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
            effect: "+1 Habileté permanente, au prix d'un peu de soi"
        ),
        "boar_meat": Info(
            name: "Hure de sanglier titanesque",
            description: "Tu as détaché un morceau de viande sombre du sanglier que tu as terrassé. Ça pèse, ça sent fort, mais ça pourra te nourrir longtemps.",
            icon: "fork.knife",
            effect: "Réserve de nourriture solide"
        ),
        "lycan_pendant": Info(
            name: "Pendentif d'argent du lycanthrope",
            description: "Collier détaché du cou d'un loup-garou abattu. Le croissant gravé t'a brûlé légèrement la paume quand tu l'as ramassé. Tu sens qu'il reconnaît la lune.",
            icon: "moon.fill",
            effect: "+2 Endurance maximum"
        ),

        // ----- Aile sud du tombeau -----

        "pit_signet": Info(
            name: "Bague de fer noire",
            description: "Glissée sous une côte effritée dans la fosse aux squelettes. Le sceau gravé n'appartient à aucune lignée connue — il porte une chaleur sourde, comme si quelqu'un tenait ta main d'en bas.",
            icon: "circle.fill",
            effect: "+1 Chance permanente"
        ),
        "silver_seal_ring": Info(
            name: "Anneau au sceau étoilé",
            description: "Anneau d'argent gravé d'une étoile à six pointes, trouvé dans un sarcophage anonyme du caveau des seigneurs. Quelqu'un a effacé tous les noms autour, mais pas le sceau.",
            icon: "star.fill",
            effect: "+1 Habileté permanente"
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
