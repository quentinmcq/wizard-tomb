//
//  EnemyCatalog.swift
//  Enemies addressed by identifier. The combat knots in adventure.ink point
//  at these ids via the `# combat: <id>` tag. The id sert aussi de nom de
//  fichier pour le portrait illustré (`tomb/Images/<id>.jpg`).
//

import Foundation

enum EnemyCatalog {

    /// Court paragraphe descriptif affiché dans le bestiaire, une fois
    /// l'ennemi vaincu. Indexé par le même id que `all`.
    static let lore: [String: String] = [
        "goblin_scout": "Petit rôdeur des sous-bois, vivant de carrioles renversées et de hachettes ébréchées. Tu en as rencontré un seul — il en court bien d'autres.",
        "marsh_serpent": "Reptile gris-vert, long comme deux hommes, qui dort sous la vase et frappe sans avertir. Sa langue mouille le visage avant la morsure.",
        "skeleton_guardians": "Deux squelettes en armure rouillée, dressés depuis cinquante ans devant la porte de fer du tombeau. Ils ne respirent plus, mais ils savent encore se battre.",
        "treasure_guardian": "Ombre de pierre qui se condense au-dessus du sarcophage volé. Bras de gravier, voix de poussière : il vient pour reprendre ce qui ne t'appartenait pas.",
        "tomb_ghoul": "Silhouette voûtée, à demi humaine, à demi pourrie. Vit dans une crypte oubliée. Garde un grimoire qu'elle ne lit plus depuis longtemps.",
        "vengeful_spirit": "Crâne flottant sous une voûte couverte d'os concentriques. Mille ans d'attente lui ont appris à parler dans la tête au lieu des oreilles.",
        "mortimer_spectre": "Sorcier scellé dans son propre tombeau il y a cinquante ans. Il ricane d'un rire sans gorge. À chacun, il décide entre les sacs et les urnes.",
        "mortimer_spectre_phase1": "Enveloppe spectrale de Mortimer — ce qu'il laisse à la surface pour décourager les premiers venus. À demi pliée, presque douce.",
        "mortimer_spectre_phase2": "Mortimer déchaîné, déployé en pleine taille. Les fresques effacées brillent autour de lui d'un trait noir. Tu as su le faire reculer — il te montre maintenant ce qu'il est vraiment.",
        "forest_wolves": "Quatre loups maigres, oreilles plates, qui n'ont pas mangé depuis trop longtemps. Leur regard ne se pose pas sur ton visage — il se pose sur ta gorge.",
        "gallery_skeletons": "Trois squelettes dont les niches funéraires servaient autrefois de cachettes. Calmes et patients comme des choses qui attendent depuis longtemps.",
        "flooded_eels": "Anguilles cuirassées qui glissent sous une eau noire. Leurs gueules tiennent plus de dents que tu n'en as jamais comptées.",
        "tomb_basilisk": "Créature lovée dans une mare d'eau noire, sourire de hyène, regard jaune-blanc. Mortimer l'a élevée pour pétrifier les indiscrets.",
        "forest_boar": "Bête énorme, défenses jaunies par les années, plus haute que toi à l'épaule. Ses yeux ne sont pas hostiles — juste lents.",
        "forest_lycanthrope": "Loup-garou marchant debout, mais c'est tout ce qu'il a d'humain. Sa gueule est plus large que la tienne. Une rangée de griffes parfaitement humaines.",
        "pit_skeletons": "Squelettes recomposés en silence dans une fosse circulaire. Le quatrième se reforme vertèbre après vertèbre pendant que tu te défends contre les trois autres."
    ]

    static let all: [String: Enemy] = [
        "goblin_scout": Enemy(
            id: "goblin_scout",
            name: "Gobelin éclaireur",
            skill: 6,
            stamina: 5
        ),
        "marsh_serpent": Enemy(
            id: "marsh_serpent",
            name: "Serpent des marais",
            skill: 7,
            stamina: 5
        ),
        "skeleton_guardians": Enemy(
            id: "skeleton_guardians",
            name: "Squelettes Gardiens",
            skill: 7,
            stamina: 8
        ),
        "treasure_guardian": Enemy(
            id: "treasure_guardian",
            name: "Gardien du trésor",
            skill: 8,
            stamina: 9,
            damageBonus: 1,
            abilityNote: "Poigne de pierre — +1 dégât par coup"
        ),
        "tomb_ghoul": Enemy(
            id: "tomb_ghoul",
            name: "Goule des oubliés",
            skill: 7,
            stamina: 7
        ),
        "vengeful_spirit": Enemy(
            id: "vengeful_spirit",
            name: "Esprit Vengeur",
            skill: 8,
            stamina: 9
        ),
        "mortimer_spectre": Enemy(
            id: "mortimer_spectre",
            name: "Spectre de Mortimer",
            skill: 9,
            stamina: 10
        ),
        "mortimer_spectre_phase1": Enemy(
            id: "mortimer_spectre_phase1",
            name: "Mortimer — enveloppe spectrale",
            skill: 8,
            stamina: 7
        ),
        "mortimer_spectre_phase2": Enemy(
            id: "mortimer_spectre_phase2",
            name: "Mortimer déchaîné",
            skill: 10,
            stamina: 11,
            damageBonus: 1,
            abilityNote: "Souffle spectral — +1 dégât par coup"
        ),

        // ----- Forêt (chap. II) -----

        "forest_wolves": Enemy(
            id: "forest_wolves",
            name: "Meute de loups",
            skill: 6,
            stamina: 6
        ),

        // ----- Donjon (chap. V) -----

        "gallery_skeletons": Enemy(
            id: "gallery_skeletons",
            name: "Squelettes de la galerie",
            skill: 7,
            stamina: 7
        ),
        "flooded_eels": Enemy(
            id: "flooded_eels",
            name: "Anguilles cuirassées",
            skill: 6,
            stamina: 5
        ),
        "tomb_basilisk": Enemy(
            id: "tomb_basilisk",
            name: "Basilic du tombeau",
            skill: 8,
            stamina: 7
        ),

        // ----- Forêt profonde -----

        "forest_boar": Enemy(
            id: "forest_boar",
            name: "Sanglier titanesque",
            skill: 7,
            stamina: 8,
            damageBonus: 1,
            abilityNote: "Charge brutale — +1 dégât par coup"
        ),
        "forest_lycanthrope": Enemy(
            id: "forest_lycanthrope",
            name: "Lycanthrope",
            skill: 8,
            stamina: 8,
            damageBonus: 1,
            abilityNote: "Griffes acérées — +1 dégât par coup"
        ),

        // ----- Aile sud du tombeau -----

        "pit_skeletons": Enemy(
            id: "pit_skeletons",
            name: "Squelettes de la fosse",
            skill: 8,
            stamina: 8
        )
    ]
}
