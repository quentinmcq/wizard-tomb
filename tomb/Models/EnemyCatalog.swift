//
//  EnemyCatalog.swift
//  Enemies addressed by identifier. The combat knots in adventure.ink point
//  at these ids via the `# combat: <id>` tag. The id sert aussi de nom de
//  fichier pour le portrait illustré (`tomb/Images/<id>.jpg`).
//

import Foundation

enum EnemyCatalog {

    static let all: [String: Enemy] = [
        "goblin_scout": Enemy(
            id: "goblin_scout",
            name: "Gobelin éclaireur",
            skill: 5,
            stamina: 4
        ),
        "marsh_serpent": Enemy(
            id: "marsh_serpent",
            name: "Serpent des marais",
            skill: 6,
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
            stamina: 9
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
            stamina: 11
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
            stamina: 8
        ),
        "forest_lycanthrope": Enemy(
            id: "forest_lycanthrope",
            name: "Lycanthrope",
            skill: 9,
            stamina: 9
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
