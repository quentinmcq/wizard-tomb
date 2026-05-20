//
//  AchievementsCatalog.swift
//  Hauts faits débloquables par le joueur au fil des parties. La progression
//  est persistée dans `GameSession.unlockedAchievements` (méta-progression,
//  survit aux runs). Une notification "burst" s'affiche au déblocage.
//

import Foundation

struct Achievement: Identifiable, Equatable, Hashable {
    let id: String
    /// Titre court affiché en gros, façon « Pacifiste ».
    let title: String
    /// Phrase descriptive d'une ligne, visible après déblocage.
    let description: String
    /// SF Symbol affiché dans la liste (icône doré quand débloqué).
    let icon: String
    /// Indice montré quand le haut fait est encore caché. Court, énigmatique.
    let hint: String
}

enum AchievementsCatalog {

    /// IDs : préfixés pour éviter toute collision UserDefaults.
    enum ID {
        static let firstBlood       = "ach.first_blood"
        static let pacifist         = "ach.pacifist"
        static let ironMan          = "ach.iron_man"
        static let collector        = "ach.collector"
        static let cartographer     = "ach.cartographer"   // toutes les fins
        static let bestiaryFull     = "ach.bestiary_full"
        static let rich             = "ach.rich"
        static let survivor         = "ach.survivor"
        static let legend           = "ach.legend"
        static let triadOfHerald    = "ach.triad"          // 3 protections vs spectre
        static let cursedAndProud   = "ach.cursed_proud"   // finir avec cursed_blade équipée
        static let widowsPromise    = "ach.widows_promise" // chaîne rendue
        static let mortimerSeesYou  = "ach.mortimer_eyes"  // voice_defy + victoire
        static let perfectRun       = "ach.perfect_run"    // Endurance >= 90% à la fin honor
    }

    static let all: [Achievement] = [
        Achievement(
            id: ID.firstBlood,
            title: "Premier sang",
            description: "Tu as remporté ton premier combat. Tes mains ne tremblent plus tout à fait pareil.",
            icon: "first_blood",
            hint: "Le premier coup qui porte change quelque chose en toi."
        ),
        Achievement(
            id: ID.pacifist,
            title: "L'ombre qui passe",
            description: "Tu as remis l'amulette à Aldwin sans avoir abattu un seul monstre. Le tombeau ne saura jamais que tu es passé.",
            icon: "leaf.fill",
            hint: "Certains terminent l'aventure sans avoir frappé personne."
        ),
        Achievement(
            id: ID.ironMan,
            title: "Le poing serré",
            description: "Tu as fini ta course sans avoir utilisé la moindre potion. Tout ce qui t'a tenu debout, c'est toi.",
            icon: "hand.raised.fill",
            hint: "Et si tu refusais le confort des fioles ?"
        ),
        Achievement(
            id: ID.collector,
            title: "Brocanteur méthodique",
            description: "Tu as ramassé au moins dix objets différents au cours d'une partie. Tu as les poches qui tintent.",
            icon: "bag.fill",
            hint: "Tu pourrais tenir un comptoir avec ce que tu trouves."
        ),
        Achievement(
            id: ID.cartographer,
            title: "Toutes les issues",
            description: "Tu as atteint chacune des cinq fins que le tombeau garde. Mortimer n'a plus rien à t'apprendre.",
            icon: "book.closed.fill",
            hint: "Cinq issues. Aucune ne se ressemble vraiment."
        ),
        Achievement(
            id: ID.bestiaryFull,
            title: "Le grand livre",
            description: "Tu as inscrit dans ton bestiaire chacune des créatures que le tombeau et la forêt cachaient.",
            icon: "pawprint.fill",
            hint: "Pour les connaître toutes, il faut les avoir affrontées toutes."
        ),
        Achievement(
            id: ID.rich,
            title: "Le sac qui pèse",
            description: "Tu as terminé une aventure avec au moins trente pièces d'or en poche. Pas mal pour un fils de fermier.",
            icon: "circle.fill",
            hint: "On peut sortir du tombeau plus riche qu'on y est entré."
        ),
        Achievement(
            id: ID.survivor,
            title: "Inentamable",
            description: "Tu as remis l'amulette à Aldwin alors qu'il te restait au moins 90 % de ton Endurance.",
            icon: "life",
            hint: "Sortir sans une égratignure, ça se mérite."
        ),
        Achievement(
            id: ID.legend,
            title: "L'épreuve du légende",
            description: "Tu as fini l'aventure en mode Légende. Personne ne te croira jamais quand tu raconteras.",
            icon: "crown.fill",
            hint: "Le mode le plus dur n'existe pas pour rien."
        ),
        Achievement(
            id: ID.triadOfHerald,
            title: "Trois fois protégé",
            description: "Tu as affronté Mortimer en portant le charme du sage, le talisman du seigneur et le sang spectral. Il a senti chacune des trois.",
            icon: "shield.lefthalf.filled",
            hint: "Trois protections s'additionnent face au spectre."
        ),
        Achievement(
            id: ID.cursedAndProud,
            title: "Lame noire au flanc",
            description: "Tu as porté la lame trempée chez la sorcière jusqu'au bout. Quelque chose en toi s'est éteint en chemin, mais tu as su l'utiliser.",
            icon: "bolt.fill",
            hint: "L'arme qui demande un prix."
        ),
        Achievement(
            id: ID.widowsPromise,
            title: "La promesse tenue",
            description: "Tu as rendu sa chaîne d'argent à la vieille femme du banc. Quinze ans de deuil s'éteignent dans son regard.",
            icon: "link",
            hint: "Quelqu'un t'attend, sur un banc, à Roncebrune."
        ),
        Achievement(
            id: ID.mortimerSeesYou,
            title: "Reconnu par le spectre",
            description: "Tu as répondu à voix haute à la chambre des voix, et tu as fini par vaincre Mortimer. Il sait maintenant qui tu es.",
            icon: "eye.trianglebadge.exclamationmark.fill",
            hint: "Une chambre cache une voix qui te ressemble."
        ),
        Achievement(
            id: ID.perfectRun,
            title: "Le pas du sage",
            description: "Tu as scellé Mortimer en élevant l'amulette au ciel. Tu deviens, pour ce qui suivra, le sorcier-protecteur de la vallée.",
            icon: "sparkles",
            hint: "Trois forces alignées dans une main droite."
        )
    ]

    static func info(_ id: String) -> Achievement? {
        all.first(where: { $0.id == id })
    }
}
