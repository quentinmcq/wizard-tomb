// =====================================================================
//  LE TOMBEAU DU SORCIER — aventure principale (Ink)
//
//  Convention de communication avec le wrapper Swift (GameSession.swift) :
//
//    # combat: <id>          → lance le combat tour-par-tour contre <id>
//    # flee_to: <knot>       → knot vers lequel fuir pendant le combat
//    # victory_path: <knot>  → knot vers lequel sauter en cas de victoire
//    # add_item: <id>        → ajoute l'objet au PlayerState (et set la
//                              variable Ink correspondante has_<id> = 1).
//                              Accepte une liste : "add_item: a, b, c".
//    # damage: <n>           → retire n points d'Endurance
//    # heal: <n>             → restaure n points d'Endurance (capé au max)
//    # spend_gold: <n>       → retire n pièces d'or
//    # luck_test             → test de Chance ; -4 Endurance si malchanceux
//    # luck_test_book        → variante : -4 Endurance si malchanceux,
//                              Chance restaurée si chanceux
//    # luck_restore          → Chance ramenée à son maximum
//    # luck_grab_amulette    → cas spécial Mortimer : chanceux = amulette,
//                              malchanceux = mort immédiate
//    # ending: victory|defeat → jingle de fin
//
//  Les knots de combat sont "vides" (juste les tags + -> END). Le wrapper
//  Swift intercepte les tags, résout le combat, puis utilise
//  moveToKnitStitch() pour relancer la story sur le bon knot.
//
//  Skill / Stamina / Luck sont gérés côté Swift ; Ink ne stocke que les
//  flags d'objets dont les choix conditionnels ont besoin. Les ids (côté
//  code) sont en anglais ; le contenu narratif reste en français.
// =====================================================================

VAR has_bronze_key         = 0
VAR has_amulet             = 0
VAR has_healing_potion     = 0
VAR has_dead_lord_talisman = 0
VAR has_stolen_loot        = 0
VAR has_rumour_mortimer    = 0
VAR has_protective_charm   = 0
VAR has_spirit_blood       = 0
VAR has_sharpened_blade    = 0
VAR has_forgotten_grimoire = 0
VAR has_widow_token        = 0
VAR has_silver_chain       = 0
// Items ajoutés par l'extension de contenu (forêt + donjon labyrinthique).
// Doivent être déclarés ici sinon setVariable("has_<item>", 1) échoue
// côté Swift et les conditionnels Ink renvoient toujours faux.
VAR has_forest_herbs       = 0
VAR has_hunter_compass     = 0
VAR has_assassin_dagger    = 0
VAR has_tomb_map           = 0
VAR has_holy_water         = 0
VAR has_runic_key          = 0
VAR has_tarnished_mirror   = 0
VAR has_basilisk_blood     = 0
// Roncebrune élargi
VAR has_priest_blessing    = 0
VAR has_hardened_skin      = 0
VAR has_necro_oil          = 0
VAR has_witch_fetish       = 0
VAR has_witch_brew         = 0
// Forêt profonde
VAR has_cursed_blade       = 0
VAR has_boar_meat          = 0
VAR has_lycan_pendant      = 0
// Aile sud du tombeau
VAR has_pit_signet         = 0
VAR has_silver_seal_ring   = 0
VAR has_mortimer_attention = 0

// Synchronisée depuis Swift au début de chaque advance() et après chaque
// spend_gold. Permet aux choix payants de se conditionner sur le solde.
VAR gold                   = 10

-> intro


// ---------- 1. Le village ----------

=== intro ===
Le village de Roncebrune meurt à petit feu depuis cinquante ans. Les récoltes pourrissent sur pied, les nouveau-nés se couvrent de taches grises, et la fontaine de la place crache une eau qui sent le métal froid. Personne ne se souvient plus du temps où l'on riait sous les tilleuls.

Maître Aldwin t'attend dans la grand-salle de sa maison, le dos voûté sous une lampe à huile. Il a le visage d'un homme qui n'a pas dormi depuis des semaines. Sa main tremble quand il te tend une pièce d'or.

« L'amulette du sorcier Mortimer a été dérobée à notre temple il y a cinquante ans, puis cachée dans son propre tombeau, à une journée de marche. Sans elle, la malédiction continue. Tu es jeune, tu es vivant, et tu es le seul qui ait accepté. Ramène-la-nous. »

Tu serres la pièce dans ton poing. Au matin, tu pars, l'épée au côté et le cœur lourd.

Avant de quitter Roncebrune pour de bon, tu prends un instant pour traverser la place. L'air est encore frais.

# chapter: village
-> village

=== village ===
La place est presque déserte. Quelques fenêtres se sont entrouvertes pour te voir partir. Au-delà de la fontaine, plusieurs ruelles s’enfoncent dans le village — certaines sont abandonnées, d’autres encore habitées.

* {not (beggar_offering and child_reward and widow_fountain and temple_priest)} [Faire le tour de la place] -> village_square
* {not (inn_rumour and forge_sharpen and apothecary and public_baths and witch_woodedge)} [Descendre dans les ruelles] -> village_alleys
* [Quitter Roncebrune pour de bon]                                  -> village_depart

=== village_square ===
Tu reprends ton tour de la place. Le pavé crisse sous tes bottes ; le tilleul mort projette une ombre maigre sur la fontaine, et chaque visage que tu croises t'évite ou t'observe trop fixement.

* {not beggar_offering} [Saluer le mendiant assis sur son sac de toile]   -> beggar
* {not child_reward} [Saluer l'enfant qui joue près du puits]             -> playing_child
* {not widow_fountain} [Parler à la veuve sur le banc de la fontaine]     -> widow_fountain
* {not temple_priest} [Pousser la porte du petit temple]                  -> temple_priest
* [Revenir au cœur du village] -> village

=== village_alleys ===
Tu t'enfonces dans les ruelles. Les volets se referment à mesure que tu passes, et l'écho de tes pas remplit des passages où aucune voix ne répond plus.

* {not inn_rumour} [Pousser la porte de l'auberge]                                       -> inn
* {not forge_sharpen} [Passer chez le forgeron]                                          -> forge
* {not apothecary} [Descendre la ruelle vers l'apothicaire]                              -> apothecary
* {not public_baths} [Profiter des bains publics avant de partir]                        -> public_baths
* {not witch_woodedge} [Pousser jusqu'à la hutte de la sorcière, à l'orée du bois]       -> witch_woodedge
* [Revenir au cœur du village] -> village

=== forge ===
La forge recrache une fumée noire qui grimpe dans l’air glacé du matin. Maître Borvic martèle une lame rougeoyante sur l’enclume sans même relever la tête lorsque tu entres. Il remarque seulement ton ombre glisser sur son établi.

« On dirait que tu pars fouiller un tombeau. Pose ton épée là. Cinq pièces, et je te la rends plus tranchante qu’un rasoir. C’est pas de la charité, c’est mon métier — et vu ta mine, tu ferais mieux d’en profiter. »

* [Payer 5 pièces d'or pour aiguiser l'épée ($5)]   -> forge_sharpen
* [Refuser et sortir]                          -> village_alleys

=== forge_sharpen ===
Borvic prend ta lame, la chauffe au rouge, la frappe sept fois sur l'enclume avec une précision d'instinct qui semble venir d'ailleurs. Quand il te la rend, encore fumante, tu sens la différence avant même de la tenir. Tu la fais tournoyer une fois. Elle a la justesse inquiétante d'une lame qui n'attend que sa première morsure.

# spend_gold: 5
# add_item: sharpened_blade

* [Le remercier et sortir] -> village_alleys

=== widow_fountain ===
Une vieille femme, tout de noir vêtue, est assise sur un banc à l’ombre d’un tilleul mort, près d’une fontaine qui crache une eau de métal. Elle tient un mouchoir entre ses doigts noueux, sans plus le porter à ses yeux : il y a longtemps qu’elle ne pleure plus, mais elle ne s’en sépare pas.

Elle tourne vers toi des yeux jaunes, rongés par la fatigue.

« Tu vas chez Mortimer ? Mon Tomas est descendu là-bas il y a quinze ans, et personne n'a su m'en dire un mot depuis. Il portait une chaîne d'argent au cou, offerte par sa grand-mère. Si tu vois quelque chose qui lui ressemble, ne me ramène pas le corps. Juste la chaîne. »

Elle te tend un petit médaillon de fer noirci, plus proche d’une promesse que d’un objet.

# add_item: widow_token

* [La saluer et retourner sur la place] -> village_square

=== inn ===
L'auberge sent la bière tiède, la sueur, et le bois humide. Trois bûcherons jouent aux dés près de l'âtre, indifférents à ton entrée. Mais un homme barbu, seul dans le coin le plus sombre, te suit du regard.

Il fait tourner un verre vide entre ses doigts.

« Tu pars pour le tombeau, on dirait. Personne ne va plus là-bas — sauf les fous. Si tu paies ma prochaine tournée, je te dis ce que je sais. »

* [Lui payer 2 pièces d'or ($2)]           -> inn_rumour
* [Refuser et sortir]                 -> village_alleys

=== inn_rumour ===
L'homme avale d'un trait sa nouvelle chope, essuie ses moustaches du revers du poignet, et se penche au-dessus de la table comme s'il craignait qu'un fantôme l'écoute.

« Mortimer n'était pas seul. Il avait un disciple, un gars du nom de Tellor, qui a fui quand le maître a commencé à parler aux morts. On dit qu'il vit encore dans la forêt à l'est, dans une cabane sous un grand chêne. Si tu le croises sur ta route, n'y passe pas sans t'arrêter. »

Il essuie du doigt une dernière goutte de bière accrochée à sa moustache.

« Et fais gaffe à l'amulette, mon gars. Mortimer y a mis plus que de la magie. »

# spend_gold: 2
# add_item: rumour_mortimer

* [Sortir de l'auberge] -> village_alleys

=== beggar ===
Près du puits, un vieux mendiant est assis sur un sac de toile. Ses yeux sont d'un gris si clair qu'on dirait deux pièces d'argent dans un visage tanné par les années. Quand il te voit, il sourit.

« Une pièce, brave voyageur, et je murmurerai ton nom aux esprits de la Chance. Ils écoutent encore les vieux mendiants, parfois. »

* [Lui donner une pièce d'or ($1)]    -> beggar_offering
* [Refuser et passer ton chemin] -> village_square

=== beggar_offering ===
Tu déposes une pièce d'or dans sa paume calleuse. Il referme ses doigts dessus et ferme les yeux. Il murmure quelque chose dans une langue que tu ne connais pas, et une douce chaleur t'envahit la nuque, comme un soleil oublié depuis longtemps.

Le vieil homme rouvre les yeux : ils sont, l'espace d'un instant, complètement blancs.

« Bonne route, fils. Et prends garde à la forêt. Elle est plus vivante qu’elle n’en a l’air. »

# spend_gold: 1
# luck_bonus: 1
# add_item: blessing

* [Continuer ton tour de la place] -> village_square

// ---------- 1bis. Roncebrune élargi ----------

=== temple_priest ===
Le temple n'est plus qu'une nef étroite, dépourvue de cloche et de fidèles. Père Cassien y vit seul, courbé sur l'autel comme un homme qui chercherait dans la pierre le nom d'une eau perdue. Il lève les yeux quand tu pousses la porte. Ils sont d'un bleu épuisé.

« Tu pars là-bas. Bien. Approche, mon fils. La protection que je peux t'offrir est maigre, mais elle a un prix — pas pour moi, pour le tronc. Sans cela, le temple n’aurait plus de toit cet hiver. »

Il désigne du menton la fente de bois où l'on jette les pièces.

* [Déposer deux pièces dans le tronc et recevoir la bénédiction ($2)] -> temple_blessing
* [Lui demander s'il a connu Mortimer] -> temple_mortimer
* [Sortir sans rien laisser] -> temple_leave

=== temple_blessing ===
Tu fais glisser deux pièces dans la fente. Le père Cassien hoche la tête, pose ses mains sur ton front. Le bois de l'autel craque doucement. Tu sens une douceur grave traverser tes épaules — non pas un feu, pas une chaleur, mais un poids qu'on retire. Tu te tiens plus droit en sortant.

Tu refermes la porte du temple derrière toi. La place te paraît un instant plus vaste qu'elle ne l'est réellement.

# spend_gold: 2
# add_item: priest_blessing
# stamina_bonus: 1
# luck_bonus: 1

* [Retourner sur la place] -> village_square

=== temple_leave ===
Tu refermes la porte du temple derrière toi sans avoir laissé la moindre pièce. La place te paraît un instant plus vaste qu'elle ne l'est réellement.
-> village_square

=== temple_mortimer ===
Le père Cassien plisse les yeux, comme si tu venais de tirer un coin de drap qu'il préférait laisser bordé.

« Mortimer ? Oui. Je l'ai connu. Il a prié ici, sous cette voûte, quand il avait ton âge. Il regardait l'autel comme tu regardes un repas qu'on t'a refusé. Quand il a tué le premier de ses morts pour lui parler, je l'ai chassé. Cinquante ans. C'est long, un homme qui crève dans un trou. »

Il sourit sans humour.

« S'il te touche, dis-lui que j'attends qu'il revienne s'agenouiller. Il comprendra. »

* [Déposer deux pièces et recevoir sa bénédiction ($2)] -> temple_blessing
* [Sortir du temple] -> temple_leave

=== apothecary ===
La boutique de mère Esmé embaume les herbes sèches, le miel chauffé et une odeur plus âcre qu’on préfère ne pas identifier. Derrière son comptoir taché, la vieille femme trie lentement des graines ridées, sans jamais lever les yeux vers toi.

« Trois fioles sur l’étagère du fond, jeune. La verte te remet sur pied quand tes tripes veulent se répandre au sol. La rouge durcit la peau quelques heures, juste assez pour survivre à une mauvaise rencontre. Et la noire… verse-en une goutte devant les morts qui marchent encore, et ils hésiteront à t’approcher. Chaque chose a son prix. »

* [Acheter la fiole verte (4 pièces — soin) ($4)] -> apothecary_green
* [Acheter la fiole rouge (5 pièces — peau dure) ($5)] -> apothecary_red
* [Acheter la fiole noire (3 pièces — repousse les morts) ($3)] -> apothecary_black
* [La saluer et sortir] -> apothecary_visit

=== apothecary_visit ===
Mère Esmé ne te rappelle pas quand tu refermes la porte. Tu remontes la ruelle.
-> village_alleys

=== apothecary_green ===
Mère Esmé glisse la fiole dans sa paume puis dans la tienne, sans la regarder.

« Tu en gardes une gorgée pour les pires moments. »

Elle replonge dans ses graines sans un mot de plus. Tu refermes la porte et tu remontes la ruelle.

# spend_gold: 4
# add_item: healing_potion

* [Reprendre les ruelles] -> village_alleys

=== apothecary_red ===
La fiole rouge est tiède. Tu la débouches et tu en bois. La peau te raidit immédiatement, comme un cuir mouillé qui sèche.

« Tu encaisseras un coup de plus avant de tomber. C'est tout ce que je vends. »

Tu refermes la porte sur l'odeur d'herbes brûlées et tu remontes vers la place.

# spend_gold: 5
# add_item: hardened_skin
# stamina_bonus: 2

* [Reprendre les ruelles] -> village_alleys

=== apothecary_black ===
Mère Esmé te tend la fiole noire avec plus de précaution que les autres.

« Si tu tombes sur un mort qui marche encore, verse une goutte à ses pieds. Ça les fait reculer et ils te laisseront tranquille. Bonne chance. »

Tu glisses la fiole dans ta ceinture et tu sors, les épaules un peu plus lourdes.

# spend_gold: 3
# add_item: necro_oil

* [Reprendre les ruelles] -> village_alleys

=== public_baths ===
Les bains de Roncebrune sont tenus par un homme placide, chauve depuis longtemps, mais qui parle avec l’assurance de quelqu’un à l’épaisse chevelure. Dans la pénombre, la grande cuve de pierre fume doucement ; l’eau, chauffée par un foyer souterrain, exhale des odeurs d’herbe humide et de cendre.

« Deux pièces d’or, et tu peux entrer. L’eau fait davantage pour un homme fatigué que la plupart des prêtres. »

* [Payer deux pièces et entrer dans la cuve ($2)] -> baths_tub
* [Refuser et sortir] -> baths_leave

=== baths_tub ===
L'eau te brûle, puis te détend. Tu y restes un long moment. Quand tu sors, des courbatures dont tu n'avais pas conscience ont disparu, et tes épaules se sont raffermies — comme si le corps avait gagné quelque chose qu'il n'avait pas en y entrant.

Tu te rhabilles, salue le tenancier d'un hochement de tête, et tu remontes la ruelle vers la place.

# spend_gold: 2
# stamina_bonus: 2

* [Reprendre les ruelles] -> village_alleys

=== baths_leave ===
Tu refermes la porte derrière toi sans avoir trempé un orteil. La ruelle est silencieuse.
-> village_alleys

=== playing_child ===
Près du puits, une enfant d'une dizaine d'années lance trois cailloux contre un mur. Elle te jette un coup d'œil. Elle a les yeux sérieux des enfants qui ont compris quelque chose que les adultes n'ont pas su leur cacher.

« Tu pars chez Mortimer. C'est pas la peine, tu sais. Mais si tu donnes un sou à ma mère elle te bénira pas, alors j'ai pensé que tu pourrais m'en donner un, moi, et que je te dirais ce que j'ai entendu. »

* [Lui glisser une pièce ($1)] -> child_reward
* [Refuser gentiment et passer ton chemin] -> village_square

=== child_reward ===
Elle empoche la pièce sans rougir et te regarde dans les yeux.

« J'ai entendu maître Aldwin parler à un autre vieux, la nuit, dans la grande salle. Il disait qu'il y a une porte dans le tombeau qui s'ouvre pas avec une clé, qu'elle s'ouvre avec une rune en argile cachée dans l'atelier de Mortimer. Si tu trouves pas la rune, tu peux pas voir la chose qui est derrière la porte. »

Elle reprend ses cailloux et te tourne le dos.

# spend_gold: 1
# luck_bonus: 1

* [Remonter sur la place] -> village_square

=== witch_woodedge ===
La hutte est à l'extrémité de la dernière ruelle, là où le pavé cède la place à l'herbe et où les autres maisons ont depuis longtemps cessé de regarder. Un fil de fumée bleue monte par le toit. La sorcière t'ouvre avant que tu n'aies frappé.

Elle a la peau colorée d'un fruit oublié au soleil. Ses dents sont parfaites, ce qui est sa façon de te dire qu'elle n'a pas l'âge qu'elle prétend.

« Entre, jeune. Je sais ce que tu vas chercher. Je peux te donner trois choses : un nom, un objet, ou un goût. Le nom, c'est gratuit. L'objet, ça coûte ton sang. Le goût, ça coûte plus. »

* [Lui demander le nom] -> witch_name
* [Lui demander l'objet (un peu de sang)] -> witch_object
* [Lui demander le goût] -> witch_taste
* [Refuser tout et partir] -> witch_leave

=== witch_leave ===
Tu refermes la porte de la hutte sans rien accepter. La sorcière ne te rappelle pas — mais ses yeux te suivent à travers les planches, jusqu'à ce que tu retrouves le pavé.
-> village_alleys

=== witch_name ===
La sorcière sourit, comme si elle te récompensait d'avoir choisi le moins gourmand.

« Tellor. C'est le nom de l'homme qu'il faut que tu trouves dans la forêt, sous un grand chêne. Il a connu Mortimer plus que personne. Il te donnera un objet contre les peurs du spectre. »

Tu refermes la porte derrière toi. Ses yeux te suivent à travers les planches jusqu'à ce que tu retrouves le pavé.

# add_item: rumour_mortimer

* [Remonter au village] -> village_alleys

=== witch_object ===
Elle t'incise le pouce avec une lame d'os et fait tomber trois gouttes dans une coupe de bois. Quand le sang touche le fond, la coupe rend une vapeur fine. Elle souffle dessus et pose dans ta paume un petit fagot d'os de poisson cousu d'un fil de cheveux blancs.

« Quand tu sentiras qu'on regarde ton dos sans qu'il y ait personne, écrase ça dans ta main. Tu auras une seconde de mieux. »

Tu glisses le fagot dans ta poche et tu sors. La ruelle te paraît plus étroite qu'à l'aller.

# damage: 2
# add_item: witch_fetish

* [Remonter au village] -> village_alleys

=== witch_taste ===
La sorcière te tend un dé à coudre rempli d’un liquide brun et sucré, qui exhale une odeur de noix grillée.

« Bois sans poser de questions. »

Tu bois. Le monde se recompose un instant — les contours se crispent, tout devient d’une netteté presque inquiétante. Ton pouls ralentit, comme s’il peinait à poursuivre sa course. Tu as la sensation qu’une lame, si elle te trouvait demain, saurait précisément où frapper. Mais le breuvage est âpre. Tu tousses, et du sang chaud éclabousse ta main avant que tu ne refermes le poing.

Tu sors de la hutte les jambes mal assurées, et tu retrouves le pavé du village comme on revient d'un rêve.

# add_item: witch_brew
# skill_bonus: 1
# damage: 3

* [Remonter au village] -> village_alleys


// ---------- 2. La route ----------

=== village_depart ===
Tu franchis la dernière maison de Roncebrune. Le pavé cède la place à une terre noire que les chariots ont creusée en deux sillons parallèles. Derrière toi, la fontaine s’est tue, et l’odeur de pain humide, celui qu’on a cuit ce matin, se dissipe déjà.

Tu te retournes une fois, juste avant la côte qui plonge sous les premiers pins. Maître Aldwin n'est pas sorti pour te saluer ; personne ne t’a accompagné jusqu’au seuil. C’est sans doute préférable — les adieux qu’on ne prononce pas sont ceux qui laissent encore la possibilité de revenir.

Le sentier s’enfonce en lacets serrés. Un vent frais, remontant de la combe, te fouette le visage.

* [Marcher en silence] -> road
* [Murmurer le nom de quelqu'un que tu laisses derrière toi] -> road_murmur

=== road_murmur ===
Tu prononces le nom à voix basse, une seule fois, et tu sens quelque chose se desserrer dans ta poitrine. Le vent l'emporte vers la combe. Quelque part, peut-être, on l'entend encore.

# luck_bonus: 1

-> road

=== road ===
Tu quittes Roncebrune par la porte de l'est. La rosée alourdit l'herbe haute, et la forêt s'ouvre devant toi comme une gueule sombre. Pendant la première heure, tu n'entends que le vent dans les pins et le crissement de tes pas sur les aiguilles sèches.

Puis tu repères une fumée mince, presque blanche, qui monte entre les branches à une centaine de pas. Quelqu'un, ou quelque chose, a fait un feu récemment.

Tu progresses entre les pins, d’un pas souple. Les fougères te caressent les jambes, et le sentier s’enfonce dans un sous-bois plus dense, que les rayons du soleil peinent à pénétrer.

À une trentaine de pas du foyer, un bruissement surgit sur ta droite. Trop sec pour un oiseau, trop léger pour un sanglier. Tu t’immobilises. Le silence retombe aussitôt — un silence qui n’a rien d’inoffensif.

Une tension froide se glisse dans le bas de ton dos, celle qui annonce qu’on n’est plus seul. Tes doigts effleurent la garde de ton épée, sans la tirer encore. Trois pas passent.

Puis le bruit revient, plus loin cette fois, déjà en train de s’éloigner.

# chapter: forest

* [Continuer avec prudence vers la fumée] -> goblin_camp

=== goblin_camp ===
Le campement est sale et abandonné depuis peu : une carriole renversée, des balluchons éventrés, et l'odeur d'un foyer encore tiède. Tu te baisses pour ramasser une chaussure d'enfant tachée de boue rouge.

Un grognement te fige. Tu te retournes lentement.

Un gobelin éclaireur, accroupi entre deux ronces, fouille frénétiquement le dernier sac intact. Quand il te repère, il bondit, hachette levée, le visage tordu d'un mélange de surprise et de fureur.

* [Le combattre]         -> fight_goblin
* [Le contourner]        -> bypass_goblin

=== fight_goblin ===
# combat: goblin_scout
# flee_to: bypass_goblin
# victory_path: goblin_defeated
-> END

=== goblin_defeated ===
La créature s'effondre dans un râle sec. Tu te baisses sur son cadavre encore chaud. Dans son sac : un quignon de pain moisi, trois cailloux peints, et une fiole de verre épais, qui sent l'herbe et la résine. Tu la glisses soigneusement dans ta ceinture.

// On laisse exprès le joueur s'enfoncer un peu plus dans la forêt avant
// d'atteindre le carrefour : la clairière offre 3 détours optionnels.

# add_item: healing_potion

* [Continuer dans la forêt] -> forest_clearing

=== bypass_goblin ===
Tu te glisses entre les fougères sans un bruit. Le gobelin grogne dans son sac, le dos tourné, ignorant ta présence à quelques pas seulement. Tu finis par rejoindre le sentier, le cœur battant la chamade.

* [Continuer dans la forêt] -> forest_clearing

// ---------- 2bis. La clairière (hub forêt) ----------

=== forest_clearing ===
Le sentier débouche sur une clairière en pente douce, ourlée de hêtres anciens qui semblent t'observer. Trois pistes s'enfoncent sous les branches.

Au nord, des pierres dressées trouent les fougères en un tracé brisé — un alignement sombre, presque humain dans leur manière de te fixer.

À l'est, l'odeur d'une fumée de bois et d'un pain qui cuit te chatouille les narines. Quelqu'un campe par là.

À l’ouest, entre deux troncs noircis, se devine le toit effondré d’une cabane. Abandonnée depuis longtemps, elle n’a plus accueilli personne depuis des années.

* {not forest_wolves} [Suivre l'alignement de pierres au nord] -> forest_wolves
* {not forest_merchant} [Aller voir le campement à l'est] -> forest_merchant
* {not forest_cabin} [Pousser jusqu'à la cabane à l'ouest] -> forest_cabin
* [Reprendre la piste vers le carrefour] -> crossroads

=== forest_wolves ===
Les pierres dressées forment un cercle imparfait. Une herbe rase et sèche les entoure, comme si rien n'avait poussé là depuis longtemps. Tu n'as pas le temps d'en faire le tour qu'un grognement bas, à hauteur de poitrine, te fige sur place.

Quatre loups maigres jaillissent d'entre les pierres, museaux écumants, oreilles plates. Ils ont eu faim trop longtemps. Tu sens leur regard ne pas se poser sur ton visage mais sur ta gorge.

* [Tirer l'épée et tenir bon] -> fight_wolves

=== fight_wolves ===
# combat: forest_wolves
# flee_to: wolves_flee
# victory_path: wolves_defeated
-> END

=== wolves_defeated ===
Le dernier loup s'écroule en travers d'un pied de pierre, langue pendante, et le silence remonte d'un coup. Tu reprends ton souffle, le bras en sang, et tu remarques alors ce que les bêtes gardaient sans le savoir : entre deux pierres, un petit ballot taché de moisi, qu'un voyageur a dû abandonner là il y a longtemps. Tu l'ouvres. Trois pièces, un mouchoir effiloché, et une poignée d'herbes vertes encore odorantes.

# add_item: forest_herbs

* [Retourner à la clairière] -> forest_clearing

=== wolves_flee ===
Tu recules sans détourner les yeux. Un des loups esquisse un bond, hésite, gronde. Tu profites du flottement pour battre en retraite jusqu'au sentier. Quand tu te retournes enfin, la clairière est silencieuse — la meute a renoncé, ou elle attend autre chose.

# damage: 1

* [Souffler un coup et choisir une autre voie] -> forest_clearing

=== forest_merchant ===
Un mulet broute paisiblement près d'une carriole couchée sur le flanc, une roue éclatée à moitié enfoncée dans la boue. Un petit homme rond, barbe rousse et chapeau de feutre, te salue d'un geste sans interrompre les jurons qu'il marmonne au timon.

« Béni soit qui m'aidera. La roue est cassée nette, et la nuit me rattrape. File-moi un coup de main et je te paie en denrées — ou en information, ou en chance, c'est selon ton goût. »

* [L'aider à relever la carriole] -> merchant_help
* [Lui offrir une pièce pour qu'il te laisse passer en paix ($1)] -> merchant_pay
* [Continuer ton chemin sans t'attarder] -> forest_clearing

=== merchant_help ===
Vous remettez la carriole d'aplomb à deux, en grognant. Le marchand recale la roue avec une cale de pierre et s'essuie le front, soulagé.

« Tiens, prends. Mon père disait qu'il fallait toujours offrir aux gens de bonne volonté ce qu'on peut leur offrir. »

Il te glisse une fiole verte poisseuse dans la main et un petit objet de bois sculpté qui ressemble à une rose des vents.

« La fiole, c'est de la décoction d'achillée — si tu prends un mauvais coup, bois ça. La boussole, ça aide à se retrouver dans la brume. Bonne route, jeune homme. »

# add_item: healing_potion, hunter_compass

* [Le saluer et reprendre la piste] -> forest_clearing

=== merchant_pay ===
Tu déposes une pièce dans sa paume. Il la fait sonner contre une autre, satisfait, et te fait un grand signe de chapeau.

« Que la chance te suive. La forêt, en ce moment, elle est pas dans son humeur la plus douce. »

Il fait un geste rapide au-dessus de tes épaules, comme un vieux rite de marchand, et il glisse sous ton col une feuille séchée pliée en quatre.

# spend_gold: 1
# luck_bonus: 1

* [Reprendre la piste vers la clairière] -> forest_clearing

=== forest_cabin ===
Tu pousses la porte de la cabane, qui pend de travers sur ses gonds rouillés. À l'intérieur, l'odeur de la cendre froide et du cuir mangé par l'humidité. Un râtelier vide, une table renversée, et au sol une cache que personne n'a vidée — la planche se soulève d'une chiquenaude.

Dedans : une lame courte, soigneusement huilée, qui n'a pas rouillé malgré les années. À côté, un mot scellé d'une encre brune que tu n'oses pas ouvrir.

* [Prendre la lame et le mot] -> cabin_search
* [Laisser tomber, l'endroit te met mal à l'aise] -> forest_clearing

=== cabin_search ===
La lame repose parfaitement dans ta paume, plus fine que ton épée, mais forgée dans un acier vif qui fredonne lorsque tu la fais tournoyer. Quant au billet, il ne porte qu’une seule phrase :

« Si tu lis ceci, c’est que je ne suis pas revenu. Ne descends pas sous les ruines sans préparation : les créatures qui dorment dans les bas fonds ne sont pas à prendre à la légère. — Brann le Chasseur. »

Tu glisses la lame dans ta ceinture.

# add_item: assassin_dagger

* [Sortir et reprendre la piste] -> forest_clearing

=== crossroads ===
Le sentier débouche sur un vieux carrefour planté en triangle au creux d'une combe. Un panneau de bois pourri pend de travers à un piquet ; on y devine encore, gravés au couteau : « marais » et « ruines ». À gauche, le sol s'abaisse vers une vallée brumeuse d'où monte une odeur sulfureuse. À droite, le sentier remonte vers des hauteurs envahies de lierre.

{has_rumour_mortimer:
Au loin, dans une clairière qu'on ne voit qu'en s'arrêtant, une silhouette en robe brune est assise sous un grand chêne, immobile. Tellor, peut-être.
}

Plus haut, sur une butte rocheuse à l'écart des trois pistes principales, les vestiges d'une vieille tour de guet se découpent dans le ciel gris. Une corneille l'a élue domicile.

* [Prendre à gauche, vers le marais]   -> marsh_approach
* [Prendre à droite, vers les ruines]  -> bridge_approach
* {has_rumour_mortimer and not forest_sage} [Aller saluer la silhouette sous le chêne ★] -> forest_sage
* {not forest_old_tower} [Grimper jusqu'à la vieille tour] -> forest_old_tower
* {not deep_forest} [S'enfoncer plus profond dans la forêt, hors des sentiers] -> deep_forest

=== forest_sage ===
# illustration: tellor
Tu t'approches lentement. L'homme ne bouge pas. Il a la peau couleur d'écorce et les yeux d'un gris si clair qu'ils semblent dépouillés de couleur. Sur ses genoux : un livre ouvert qu'il ne lit pas.

« Tellor, c'est mon nom. Tu vas au tombeau de mon ancien maître. Je le savais. Roncebrune ne mourra pas sans qu'on essaie. »

Il referme son livre.

« Mortimer était un homme avant d'être un sorcier, vois-tu. Quand il a commencé à parler aux morts, je lui ai dit non. Il m'a banni. Cinquante ans plus tard, c'est moi qui suis encore là, et lui qui rampe au fond d'un trou. C'est une justice étrange. »

Tellor pose une main sèche sur ton épaule.

« Prends ceci. C'est un charme d'os et de fil rouge, vieux comme moi. Quand le spectre tentera de te briser par la peur, il sentira mon souvenir, et il hésitera. Et écoute-moi bien, jeune. L'amulette que tu vas chercher, ce n'est pas qu'un objet. Mortimer y a scellé une part de lui. Ramène-la si tu dois, mais ne la garde pas trop longtemps. »

# add_item: protective_charm
# luck_restore

* [Le remercier et reprendre la route] -> crossroads

=== forest_old_tower ===
Tu grimpes le sentier rocheux jusqu'aux ruines de la tour. La porte basse a disparu il y a longtemps — il ne reste qu'une arche écroulée. À l'intérieur, un escalier en colimaçon mangé à demi par le lierre monte vers une plateforme à moitié effondrée.

L'air sent la pierre humide et la fiente d'oiseau. Sur une marche, un crâne humain blanchi par la pluie — un voyageur, peut-être, ou le guetteur d'autrefois.

* [Monter à la plateforme] -> tower_platform
* [Fouiller le bas de la tour, autour du crâne] -> tower_search
* [Sortir, l'endroit te met mal à l'aise] -> crossroads

=== tower_platform ===
Tu montes prudemment, marche après marche, en évitant les trous où le bois a fini de pourrir. La plateforme est éventrée mais ouverte sur toute la vallée. Tu vois Roncebrune au loin, le marais à gauche, les ruines à droite, et même la silhouette grise de Mortimer qui semble vibrer dans l'air, comme une fièvre du sol.

À tes pieds, un parchemin roulé dans un tube de cuivre verdi. Tu l'ouvres. C'est un plan grossier des couloirs sous les ruines — un labyrinthe avec des annotations à l'encre sépia.

# add_item: tomb_map
# luck_bonus: 1

* [Redescendre] -> crossroads

// ---------- 2ter. Forêt profonde (sous-hub) ----------

=== deep_forest ===
Tu quittes la piste et tu t'enfonces sous les fougères, les ronces, les hêtres centenaires aux troncs tordus comme des hommes qui auraient longtemps souffert. Le sol monte, descend, change de texture à chaque trentaine de pas. Tu n'es plus sûr de la direction du sud.

Tu débouches dans une clairière de fougères plus haute que toi. Plusieurs choses te frappent :

Au nord, le sol porte des empreintes énormes — fendues, comme celles d'un sanglier que personne n'a chassé depuis longtemps.

À l'est, un fil de fumée monte entre deux fûts d'un grand chêne mort. La hutte d'une sorcière, on en murmure dans Roncebrune.

À l'ouest, des pierres taillées affleurent à demi-enfouies — les vestiges d'un autel à un dieu qui n'a plus de nom.

Au sud, sous un buisson, tu repères un loup mort. Pas un loup ordinaire — un loup avec des mains.

* {not forest_boar_scene} [Suivre les traces de sanglier au nord] -> forest_boar_scene
* {not witch_hut} [Aller voir la hutte à l'est] -> witch_hut
* {not forest_sanctuary} [Dégager les pierres à l'ouest] -> forest_sanctuary
* {not forest_lycanthrope_scene} [Examiner le loup au sud ★] -> forest_lycanthrope_scene
* [Retourner au carrefour] -> crossroads

=== forest_boar_scene ===
Tu suis les traces sur une cinquantaine de pas, et tu débouches sur l'animal lui-même : un sanglier énorme, des défenses jaunies par les années, plus haut que toi à l'épaule. Il broute, indifférent — jusqu'à ce qu'il te repère. Ses yeux ne sont pas hostiles. Ils sont juste lents.

Quand il charge, c'est sans avertissement et avec toute la masse de son corps.

* [Tenir la position, lame haute] -> fight_boar
* [Bondir hors du chemin et fuir] -> boar_flee

=== fight_boar ===
# combat: forest_boar
# flee_to: boar_flee
# victory_path: boar_defeated
-> END

=== boar_defeated ===
La bête s'effondre dans un grondement qui finit en gargouillis. Tu reprends ton souffle, le dos contre un tronc. Quand tu te penches sur la carcasse, tu trouves dans son flanc une lame brisée — un fer ancien, gravé d'une rune, qu'un chasseur a laissé là il y a bien longtemps. Tu détaches aussi un morceau de hure : la viande te servira.

# add_item: boar_meat
# skill_bonus: 1

* [Retourner à la clairière profonde] -> deep_forest

=== boar_flee ===
Tu plonges sur le côté juste à temps. La défense te frôle la cuisse — tu sens le tissu se déchirer mais pas la peau. Tu cours sans te retourner.

# damage: 2

* [Te ressaisir à la clairière profonde] -> deep_forest

=== witch_hut ===
La hutte s'enfonce dans le tronc d'un chêne mort, comme si l'arbre avait poussé autour. La porte est entrouverte. À l'intérieur, à la lumière d'une chandelle, la même sorcière que tu as vue à Roncebrune (si tu l'y as vue) — ou alors quelqu'un qui lui ressemble assez pour être sa sœur.

{has_witch_fetish or has_witch_brew:
« Tu reviens. Bien. La forêt te change, elle finira par te demander quelque chose de toi en échange. »
- else:
« Première fois ici. La forêt te change, vois-tu. Elle finira par te demander quelque chose de toi en échange. »
}

Elle te désigne un foyer où mijote une marmite à l'odeur de boue et de sang séché.

« Trempe ta lame là-dedans. Trois minutes. Ça la rendra plus tranchante que le mot d'un mort. Mais quelque chose qui te tient à cœur s'en ira, je ne sais pas quoi. »

* [Tremper la lame dans la marmite] -> hut_blade
* [Refuser et reculer] -> hut_refuse

=== hut_blade ===
Tu trempes la lame trois minutes pleines. Quand tu la ressors, elle est noire comme du bois brûlé et coupe l'air d'un sifflement sec. Mais tu sens une absence — comme un nom que tu n'arriveras plus à prononcer.

# skill_bonus: 1
# damage: 2
# add_item: cursed_blade

* [La remercier et sortir] -> deep_forest

=== hut_refuse ===
Tu sors de la hutte. La sorcière ne te rappelle pas, mais quand tu refermes la porte, tu entends son rire à travers les planches — un rire sec, presque amical.

* [Retourner à la clairière profonde] -> deep_forest

=== forest_sanctuary ===
Tu dégages les pierres à mains nues. Sous la mousse et la terre, un autel circulaire émerge, gravé d'un visage de bois aux yeux clos. Une bouche d'argile en lame mince forme une fente au creux de la pierre. Tu reconnais l'iconographie de ces dieux que les chrétiens ont enterrés plutôt que de les nommer.

Une voix sans corps te traverse :

« Donne quelque chose et tu prendras quelque chose. »

* [Y déposer deux pièces ($2)] -> sanctuary_gold
* [Y déposer la moitié de ton sang en mordant ta main] -> sanctuary_blood
* [Ne rien donner, partir poliment] -> deep_forest

=== sanctuary_gold ===
Tu laisses tomber les deux pièces dans la fente. Elles ne sonnent pas. Tu sens une chaleur monter de l'autel, douce et lourde — comme si quelqu'un te posait une cape de plomb tiède sur les épaules.

# spend_gold: 2
# heal: 4
# luck_restore

* [Te redresser, te recueillir un instant, partir] -> deep_forest

=== sanctuary_blood ===
Tu mords ta main et tu laisses couler dans la fente. Le sang fume au contact de l'argile. Le visage de bois sourit — une seconde, pas plus.

Tu te sens vidé, et plus solide. Le dieu oublié te garde dans son repli.

# damage: 3
# skill_bonus: 1
# luck_bonus: 1

* [Repartir, le pas plus calme] -> deep_forest

=== forest_lycanthrope_scene ===
Le loup a la taille d'un homme, et ce sont bien des mains de chair humaine qui dépassent de ses pattes avant. Une rangée de griffes parfaitement humaines, taillées comme on taille des ongles. Il est mort depuis quelques heures, gorge tranchée nette, et tu n'as pas le temps de te demander qui a fait ça que tu sens, dans ton dos, un grognement.

Un second lycanthrope, vivant, jaillit des fourrés. Il marche debout, mais c'est tout ce qu'il a d'humain. Sa gueule est plus large que la tienne.

* [L'affronter] -> fight_lycanthrope

=== fight_lycanthrope ===
# combat: forest_lycanthrope
# flee_to: lycanthrope_flee
# victory_path: lycanthrope_defeated
-> END

=== lycanthrope_defeated ===
Le lycanthrope s'effondre sur le cadavre de son congénère — étrange, deux frères tombés à la même place. Tu prends le temps de regarder. Sur le mort frais, autour du cou, un collier d'argent gravé d'un croissant. Tu le détaches.

L'argent te brûle légèrement la paume, comme si une charge en sortait. Tu sais maintenant que tu n'oublieras plus l'éclat de la lune pleine.

# add_item: lycan_pendant
# stamina_bonus: 2

* [Repartir, vivant] -> deep_forest

=== lycanthrope_flee ===
Tu détales dans les fougères. Tu sens la respiration de la bête derrière toi pendant trente pas, puis quarante. Quand tu te retournes enfin, elle a renoncé — pour cette fois. Tu boites jusqu'à la clairière.

# damage: 4

* [Te ressaisir] -> deep_forest

=== tower_search ===
Tu fouilles méthodiquement autour du crâne. Sous une dalle disjointe, une cache que personne n'a vue depuis des années : une petite fiole bouchée de cire noire — eau bénite, à en croire la croix gravée sur le bouchon — et quelques pièces d'or oubliées dans la mousse.

# add_item: holy_water
# gain_gold: 3

* [Empocher et redescendre] -> crossroads

=== bridge_approach ===
Tu prends la piste qui remonte vers les hauteurs. Le sentier devient pierreux, puis franchement abrupt. Tu t'arrêtes deux fois pour souffler, et à chaque fois tu vois plus de la vallée derrière toi : les toits gris de Roncebrune, la fumée qui ne s'élève plus qu'à peine.

Le lierre envahit tout — il étouffe les vieux bornes de pierre que personne ne taille depuis des décennies. Tu en vois une, à demi recouverte, qui porte une inscription effacée et un sablier sculpté. Un poste de garde, jadis. Personne ne garde plus rien sur cette route.

Vers l'avant, le sentier monte encore, puis disparaît. Un bruit de torrent monte d'en bas, comme un avertissement.

* [Continuer la montée] -> bridge_broken

=== bridge_broken ===
Le sentier monte le long d'un ravin de plus en plus profond. Un vieux pont de bois le franchit — mais il pend de travers, vieilli par les pluies, et la moitié de ses planches a fini en bas. Le vide te tire dans l'estomac quand tu jettes un œil par-dessus.

* [Sauter par-dessus les planches manquantes] -> bridge_jump
* [Descendre prudemment au fond du ravin]     -> bridge_around

=== bridge_jump ===
Tu recules de trois pas, prends ton élan et sautes. Le monde se réduit, pendant une seconde, à un bruit de vent et à la sensation très précise du vide sous tes bottes.

# luck_test

* [Te relever et continuer] -> ruins

=== bridge_around ===
Tu descends au fond du ravin par une faille latérale. Le ruisseau qui coule en bas est noir, stagnant par endroits, vif ailleurs. Tu le franchis sur des pierres, remontes par l'autre versant. Tu as perdu une bonne heure mais tu arrives entier.

* [Continuer vers les ruines] -> ruins


// ---------- 3. Le marais ----------

=== marsh_approach ===
Tu descends vers la vallée brumeuse. Les pins cèdent la place à des aulnes maigres, puis à des roseaux secs qui te griffent les mollets. Le sol devient mou — d'abord élastique, puis franchement humide, puis traître.

L'odeur change avant la végétation. Sulfure, vase, quelque chose de plus ancien. Quand tu inspires longtemps tu sens un goût de métal au fond de la gorge.

Tu vois apparaître entre les troncs la première mare stagnante — noire, immobile, parfaitement lisse comme un miroir qui aurait oublié comment refléter.

* [Avancer dans le marais] -> marsh

=== marsh ===
Tes bottes s'enfoncent dans une boue noire qui aspire et claque à chaque pas. L'air pue le soufre et la matière en décomposition. Des bulles crèvent à la surface des mares stagnantes, sans qu'aucune vie n'y soit visible.

Un froissement de roseaux te fait tourner la tête. Trop tard. Un serpent géant, gris-vert et long comme deux hommes, jaillit d'une eau noire et siffle en se dressant.

Au même moment, à une vingtaine de pas, sur un radeau qui dérive dans la brume, une silhouette encapuchonnée te fait un signe lent de la main.

{has_hunter_compass:
La rose des vents tremble dans ta poche, insistante. Elle pointe vers la gauche — une langue de terre sèche, presque invisible sous la brume, qui contourne les roseaux et le serpent. Tu la vois maintenant que tu sais qu'elle est là.
}

# chapter: marsh

* [Combattre le serpent maintenant]      -> fight_serpent
* [Faire signe à la silhouette]           -> marsh_merchant
* {has_hunter_compass} [Suivre la boussole sur la langue de terre sèche ★] -> marsh_compass

=== marsh_merchant ===
La marchande approche son radeau d'une perche silencieuse. Sous son capuchon, tu n'aperçois qu'une bouche, fendue d'un sourire trop fin. Elle déploie un étal de fortune sur le radeau : fioles troubles, dagues en os, runes gravées sur des vertèbres.

« Trois pièces d'or, et tu as ma potion. La meilleure du marais, je te le jure sur l'ombre de ta mère. »

Le serpent gronde toujours dans les roseaux, prêt à frapper.

* [Acheter la potion (3 pièces d'or) ($3)]   -> merchant_buy
* [Refuser et faire face au serpent]    -> fight_serpent

=== merchant_buy ===
La marchande te tend une fiole verte poisseuse, attrape les pièces sans les regarder, et son radeau s'éloigne déjà avant que tu n'aies repris ton souffle. Tu glisses la fiole sous ta cape — la garder bouchée vaut mieux que la boire pour rien.

Le serpent attend toujours, sa langue dardée vers toi.

# spend_gold: 3
# add_item: healing_potion

* [Affronter le serpent]                              -> fight_serpent
* [Fuir tant qu'il en est encore temps]               -> ruins_after_flee

=== fight_serpent ===
# combat: marsh_serpent
# flee_to: ruins_after_flee
# victory_path: serpent_defeated
-> END

=== marsh_compass ===
Tu suis la rose des vents pas à pas, contournant l'eau noire par une crête de terre que la brume cachait. Le serpent siffle encore dans ton dos, déjà loin, et finit par retomber dans la vase. Tu n'y laisses ni sang ni cri — juste tes bottes alourdies de boue.

Mais ce que la brume t'a fait éviter, elle te l'a aussi caché : tu sors du marais sans la clé de bronze que les autres voyageurs ont trouvée dans la vase. Tu devras te débrouiller autrement à l'entrée du tombeau.

* [Reprendre la marche vers les ruines] -> ruins

=== serpent_defeated ===
Tu écrases la tête du reptile entre deux pierres, à la fin d'un combat long et boueux. Ton bras tremble encore quand tu te relèves. Quelque chose brille dans la vase, près de l'endroit où le serpent s'est dressé pour la première fois.

Tu plonges la main jusqu'au coude. Une clé. Bronze verdi par les siècles, sa garde gravée d'une rune que tu ne reconnais pas. Elle est lourde, presque chaude.

# add_item: bronze_key

* [Continuer vers les ruines] -> ruins

=== ruins_after_flee ===
Tu cours, jambes lourdes, le serpent à tes trousses. Les roseaux te fouettent le visage. Quand tu atteins enfin la pierre sèche des ruines, tu t'écroules contre un mur, le souffle court, le sang battant aux tempes.

# damage: 2

* [Reprendre ton souffle] -> ruins


// ---------- 4. Les ruines, entrée du tombeau ----------

=== ruins ===
Les ruines d'un ancien temple qui ne servait plus à personne, déjà à l'époque où Mortimer y a fait creuser sa tombe. Des colonnes brisées s'enfoncent dans la mousse. Un autel défoncé sert encore d'abri à des nichées de souris.

Au centre, un escalier de pierre descend dans une obscurité que la lumière du jour refuse de pénétrer. C'est l'entrée du tombeau. Tu sens le souffle froid qui en monte avant même de l'apercevoir.

{has_bronze_key:
La clé de bronze pèse dans ta poche comme si elle savait qu'elle allait servir.
}

À l'écart, derrière un éboulement de pierres, tu aperçois la béance d'une autre entrée — une crypte plus ancienne que le tombeau lui-même, ouverte par les pluies de l'hiver dernier. L'odeur qui en sort n'est pas tout à fait celle des morts ordinaires.

# chapter: ruins

* [Descendre dans le tombeau de Mortimer]    -> tomb_descent
* {not forgotten_crypt} [Explorer la crypte ouverte ★] -> forgotten_crypt

=== forgotten_crypt ===
Tu descends quelques marches usées dans une voûte basse, plus ancienne que celle du tombeau principal. L'odeur, ici, est âcre — celle de la chair qui a oublié de mourir tout à fait. Au fond, sur un tas d'ossements méticuleusement empilés, un grimoire à la couverture de cuir bordeaux semble t'attendre.

Une silhouette voûtée se redresse soudain entre toi et le livre. Une goule, à demi humaine, à demi pourrie, dont les yeux blancs te fixent sans surprise.

* [La combattre]                       -> fight_ghoul

=== fight_ghoul ===
# combat: tomb_ghoul
# flee_to: ruins
# victory_path: ghoul_defeated
-> END

=== ghoul_defeated ===
La goule s'effondre dans un râle de gorge sèche, et se replie sur elle-même comme un sac de cuir vide. Tu enjambes ses restes pour ramasser le grimoire. Quand tu l'ouvres, tu sens immédiatement quelque chose se débloquer en toi, comme une porte qui s'ouvre dans un mur que tu n'avais pas vu.

Tes idées sont plus rapides, et tu sens que ce livre ne te quittera plus avant la fin de l'aventure.

# add_item: forgotten_grimoire

* [Remonter et reprendre ta quête] -> ruins

=== tomb_descent ===
Tu passes sous l'arche de pierre noircie. Une volée de marches courtes s'enfonce dans le sol, taillées dans le roc à coups d'outils qu'on ne fabrique plus. La lumière du jour se rétrécit derrière toi, puis se réduit à un trait, puis disparaît.

L'air change deux fois. D'abord la fraîcheur normale des sous-sols. Puis, vers la trentième marche, un froid sec qui te pince la nuque et qui ne ressemble à aucune température connue. Ce n'est plus de l'air ordinaire que tu respires — c'est quelque chose qui attend.

{has_tomb_map:
Tu sors le plan grossier du tombeau. Tu reconnais l'escalier principal, et tu vois où il débouche : sur une porte de fer gardée par deux silhouettes. Le plan annote, à l'encre sépia : « ne pas réveiller s'ils dorment ».
- else:
Sans plan, tu descends en tâtonnant, l'épaule contre la paroi humide. Tu comptes les marches jusqu'à perdre le compte.
}

L'escalier finit par mourir. Au pied de la dernière marche : une lourde porte de fer, scellée par une chaîne, et devant elle, dressés comme s'ils t'attendaient depuis toujours, deux squelettes en armure rouillée. Leurs orbites vides te suivent.

L'un d'eux tire sa lame en grinçant. L'autre lève un bouclier troué.

# chapter: tomb

* [Les combattre]                                              -> fight_skeletons
* {has_bronze_key} [Glisser la clé dans la serrure de côté ★] -> secret_passage

=== fight_skeletons ===
# combat: skeleton_guardians
# victory_path: skeletons_defeated
-> END

=== skeletons_defeated ===
Les ossements s'éparpillent sur la dalle dans un bruit sec. Tu pousses la porte de fer en grognant ; elle cède dans un raclement long. Derrière, le couloir attendait depuis des siècles.

* [Franchir la porte] -> corridor_entry

=== secret_passage ===
La clé tourne dans une serrure dissimulée derrière une dalle inclinée. Un déclic, et un passage étroit s'ouvre dans le mur, à hauteur d'un homme accroupi. Tu te glisses dedans sans bruit, laissant les squelettes immobiles, leurs orbites tournées vers une menace qui n'est plus là.

* [Continuer] -> corridor_entry


// ---------- 5. Le tombeau ----------

=== corridor_entry ===
Tu débouches dans un couloir bas tapissé de toiles d'araignées poussiéreuses. Sur ta gauche, une petite porte de bois pourrissant que la moisissure a fait gondoler. À droite, le couloir principal continue dans l'obscurité.

{has_widow_token and not has_silver_chain:
Près du seuil, à demi enseveli sous la poussière, un squelette est affalé contre le mur. Au cou, une fine chaîne d'argent encore intacte. Tu reconnais le travail décrit par la vieille femme. Tu la décroches en silence.

# add_item: silver_chain
}

* [Pousser la porte de bois ★]            -> forgotten_library
* [Continuer dans le couloir principal]   -> corridor

=== forgotten_library ===
La porte cède dans un soupir, et tu entres dans une pièce envahie de poussière fine. Des étagères croulent sous des grimoires moisis, leurs reliures à demi mangées par les rats. Au centre, sur un pupitre de pierre, un volume est ouvert : ses pages de parchemin sont noires d'encre fraîche, comme si quelqu'un venait juste de l'écrire.

Le silence est anormal. L'air ne sent pas la poussière, mais une humidité métallique.

* [L'ouvrir et lire à voix basse]    -> book_read
* [Quitter sans rien toucher]        -> corridor

=== book_read ===
Tu lis à mi-voix la première phrase. Les lettres se mettent à frémir sous tes yeux, comme si elles essayaient de t'échapper. La pièce semble respirer. Tu sens des doigts froids te frôler la nuque sans qu'aucune main n'apparaisse.

# luck_test_book

* [Refermer le livre, sortir, vite] -> corridor

=== corridor ===
Un long couloir s'étire devant toi, ses dalles couvertes de motifs spiralés qu'on dirait gravés au couteau. Plusieurs portes y donnent, et même un pan d'escalier mort que la mousse a fini d'avaler.

À mi-parcours sur ta gauche, une porte entrouverte laisse filtrer une lueur dorée — la lumière qui sort de là est trop chaude pour être naturelle.

Plus loin sur ta droite, une autre porte massive, marquée d'un soleil noir, laisse passer une lueur glaciale et bleutée.

Au fond à gauche, un boyau bas s'ouvre vers un clapotis lointain d'eau.

À droite encore, une porte gravée d'alambics et de cornues : un atelier, à n'en pas douter.

{has_tomb_map:
Ton plan grossier indique qu'au-delà du couloir, l'escalier principal mène à la chambre voûtée. Les autres salles sont marquées d'un ☥ — risque, ou récompense, ou les deux.
}

* [Continuer droit, prudemment]               -> trap_room
* [Pousser la porte dorée]                    -> treasure_room
* [Aller voir la lumière bleue ★]             -> forgotten_chapel
* {not gallery_skeletons_scene} [S'enfoncer dans le boyau qui chante l'eau] -> gallery_skeletons_scene
* {not mortimer_lab} [Pousser la porte de l'atelier] -> mortimer_lab
* {not south_wing} [Forcer la herse rouillée au sud] -> south_wing

=== gallery_skeletons_scene ===
Le boyau s'élargit en une galerie longue où des niches funéraires creusent le mur des deux côtés, tous les trois pas. La plupart sont vides. Quelques-unes contiennent encore un corps en armure rouillée, immobile, mais sans le sommeil d'un mort.

À ton premier pas, une niche claque sec. Un squelette tombe d'à-pic au milieu du couloir, lame brandie. Deux autres se redressent à tes flancs. Trois en tout, calmes et patients comme des choses qui attendent depuis longtemps.

* [Continuer dans la galerie] -> fight_gallery
* [Reculer vers le couloir] -> corridor

=== fight_gallery ===
# combat: gallery_skeletons
# flee_to: corridor
# victory_path: gallery_defeated
-> END

=== gallery_defeated ===
Les ossements s'effondrent les uns sur les autres dans un cliquetis qui résonne longtemps dans la galerie. Le silence revenu, tu enjambes les restes et tu pousses jusqu'au bout du boyau, où l'eau clapote pour de bon.

* [Continuer vers la source du bruit] -> water_room

=== water_room ===
Tu débouches dans une vaste salle dont la moitié basse est inondée. L'eau noire t'arrive aux genoux. Au plafond, des chaînes pendent comme des lianes mortes. Au centre, une plateforme de pierre émergeant à peine, et sur cette plateforme, posé sur un coussin d'algues sèches, un petit miroir cerclé d'argent terni.

Quelque chose ondule sous la surface. Trois formes longues, presque transparentes, glissent vers toi en zigzag.

* [Patauger jusqu'au miroir, lame haute] -> fight_eels
* [Tenter de bondir d'une chaîne à l'autre jusqu'à la plateforme] -> water_room_acrobat
* [Reculer vers la galerie] -> corridor

=== fight_eels ===
# combat: flooded_eels
# flee_to: corridor
# victory_path: eels_defeated
-> END

=== eels_defeated ===
La dernière anguille se vide dans un dernier soubresaut. L'eau autour de toi vire au noir vraiment noir. Tu grimpes sur la plateforme, ruisselant, et tu prends le miroir : sa surface est si terne qu'on n'y voit rien — et c'est probablement pour ça qu'il a été oublié ici.

# add_item: tarnished_mirror

* [Sortir par la porte du fond] -> profane_sanctuary
* [Faire demi-tour vers le couloir] -> corridor

=== water_room_acrobat ===
Tu sautes sur la première chaîne, qui te taillade la paume mais tient bon. Tu te balances, attrapes la suivante. Tes pieds frôlent la surface noire, et tu vois passer en dessous une gueule trop grande et trop garnie de dents pour un poisson.

# luck_test

* [Atterrir sur la plateforme] -> eels_defeated_easy

=== eels_defeated_easy ===
Tu atteins la plateforme sans y laisser un orteil. Le miroir terni est entre tes mains avant que les bestioles aient compris ce qui leur passait au-dessus du nez.

# add_item: tarnished_mirror

* [Sortir par la porte du fond] -> profane_sanctuary
* [Repartir par où tu es venu] -> corridor

=== profane_sanctuary ===
Tu débouches dans une chapelle profanée si petite qu'elle ressemble à un placard sacré. L'autel a été retourné, les cierges écrasés, le crucifix de bronze cassé en deux. Mais derrière une dalle disjointe, quelqu'un a caché ce que Mortimer cherchait visiblement à détruire : une fiole d'eau bénite, intacte sous sa cire, et un parchemin d'incantation.

# add_item: holy_water

* [Empocher et sortir] -> corridor

=== mortimer_lab ===
La porte cède dans un crissement et tu entres dans ce qui ressemble à l'atelier d'un alchimiste fou. Des étagères pliant sous le poids de fioles, de cornues, de chaudrons recouverts de poussière. Une table maculée de taches noires, où traîne encore une plume d'oie et un cahier ouvert sur des notes en latin de cuisine.

L'air ici est saturé de vapeurs âcres — un demi-siècle d'alchimie qui n'a jamais cessé de fermenter dans les fioles ouvertes. Tu inspires malgré toi et un haut-le-cœur te plie en deux ; tes poumons brûlent. Tu perds un point d'Endurance avant d'avoir touché à quoi que ce soit.

# damage: 1

Sur le cahier, une page t'attire l'œil : un dessin de porte, marquée de trois runes, et la mention « ouvre seule à la rune-clé d'argile, gardée au fond de mes salles ».

* [Fouiller les étagères pour la "rune-clé"] -> lab_search
* [Lire les notes pour comprendre ce que Mortimer cherchait] -> lab_read
* [Sortir au plus vite, l'air te tord les poumons] -> corridor

=== lab_search ===
Tu écartes les flacons un à un. La plupart sont brisés ou ne contiennent plus qu'une croûte sèche. Mais dans une boîte de bois calcinée, tu mets la main sur une petite tablette d'argile gravée de trois signes — la rune-clé.

# add_item: runic_key

* [Empocher et explorer la suite] -> rune_chamber
* [Repartir au couloir] -> corridor

=== lab_read ===
Le cahier décrit, dans une langue que tu déchiffres péniblement, la façon dont Mortimer a scellé son amulette derrière une porte runique — et comment cette porte ne s'ouvre qu'à la rune-clé d'argile cachée au labo. Si tu rentres bredouille, tu pourras toujours forcer l'amulette par le chemin direct.

# luck_bonus: 1

* [Fouiller pour trouver la rune-clé] -> lab_search
* [Retourner au couloir] -> corridor

=== rune_chamber ===
Tu descends quelques marches et tu débouches dans une antichambre dont le seul mur lisible porte une porte de bronze gravée de trois runes concentriques. La rune centrale présente une empreinte profonde, taillée pour recevoir un objet précis.

{has_runic_key:
Tu appliques la tablette d'argile sur l'empreinte centrale. Les runes s'allument d'une lueur sourde, et la porte bascule sans un bruit, comme un livre qui s'ouvre.

* [Franchir la porte] -> basilisk_cave
* [Repartir au couloir] -> corridor
}
{not has_runic_key:
Tu tâtes l'empreinte du bout des doigts. Le bronze refuse de céder, et tu n'as rien qui rentre dans la cavité. Il te faudrait la rune-clé d'argile pour franchir cette porte — sans elle, mieux vaut renoncer.

* [Repartir au couloir] -> corridor
}

=== basilisk_cave ===
Tu descends un escalier brutal dans une caverne naturelle dont les parois sont couvertes d'écailles fossilisées. Au centre, dans une mare d'eau noire, une créature lovée sur elle-même se redresse à ton approche — un basilic de la taille d'un poney, gueule fendue d'un sourire de hyène, yeux qui brillent d'une lumière jaune-blanc.

{has_tarnished_mirror:
Tu sors le miroir terni et tu en orientes l'éclat vers le basilic. Il siffle, recule, ses yeux ne supportent pas sa propre image. Tu as ton ouverture.
}
{not has_tarnished_mirror:
Tu détournes les yeux du regard de la bête juste à temps. Un froid bizarre te traverse la nuque — un instant de plus et tu te serais pétrifié.
}

* [L'affronter] -> fight_basilisk
* [Fuir, dos contre le mur] -> basilisk_flee

=== basilisk_flee ===
Tu remontes l'escalier en titubant, dos collé au mur. Le sifflement de la créature t'accompagne longtemps après que la mare ait disparu derrière toi. Quelque chose dans la nuque te brûle — son regard t'a effleuré.

# damage: 3

* [Reprendre le couloir] -> corridor

=== fight_basilisk ===
# combat: tomb_basilisk
# flee_to: corridor
# victory_path: basilisk_defeated
-> END

=== basilisk_defeated ===
Le basilic s'effondre dans un sifflement qui s'éteint dans la mare. Tu fouilles la berge et tu trouves, presque enseveli dans la vase, un coffret d'os fermé d'une serrure d'argent. Il contient une fiole épaisse et tiède : du sang de basilic, dont la légende dit qu'il rend la vue plus claire que la lumière du jour.

# add_item: basilisk_blood
# luck_bonus: 1
# heal: 3

* [Remonter au couloir] -> corridor

=== treasure_room ===
La salle déborde de richesses comme un rêve d'enfant. Pièces, gobelets, bracelets, lingots ; les murs sont eux-mêmes incrustés de plaques d'or martelé. Au centre, sur un sarcophage de pierre noire, une silhouette est sculptée les bras croisés sur la poitrine — un seigneur antique, paisible, d'une beauté qui n'appartient plus qu'aux morts.

L'inscription, à demi effacée par l'eau qui suinte de la voûte :

« Que celui qui me dépouille périsse de ma main. »

* [Ramasser une poignée d'or]          -> treasure_taken
* [Incliner la tête et ressortir]      -> treasure_respected

=== treasure_taken ===
Tu remplis ta bourse de pièces, en silence, avec un sang-froid qui ne te ressemble pas. Tu ne sens d'abord rien. Puis le froid descend, lent, depuis la voûte. Une ombre se condense au-dessus du sarcophage. Des bras de pierre se déplient avec un bruit de gravier.

# add_item: stolen_loot
-> fight_guardian

=== fight_guardian ===
# combat: treasure_guardian
# victory_path: guardian_defeated
-> END

=== guardian_defeated ===
Le gardien se déchire en poussière et retombe sur lui-même, vidant le sarcophage de son occupant pour de bon. Le froid reflue. Tu pars d'un pas plus lourd, ta bourse alourdie d'un or qui ne t'a pas tout à fait pardonné.

* [Retourner au couloir] -> corridor

=== treasure_respected ===
Tu poses une main sur la pierre froide du sarcophage et tu inclines la tête, longuement. Quelque chose dans la salle se relâche, comme un mur qui aurait retenu son souffle. Sur la pierre noire, un petit objet apparaît — un talisman gris-cendre, simple, qui semble t'attendre. Tu le glisses dans ta poche.

Une vague de chaleur t'envahit, comme si tu venais d'avaler une gorgée d'eau-de-vie.

# add_item: dead_lord_talisman
# heal: 3

* [Retourner au couloir] -> corridor

=== forgotten_chapel ===
Une chapelle profanée. Le sol est jonché d'ossements rangés en cercles concentriques — un esprit méticuleux a passé du temps là. Au centre, un autel à la pierre noircie. Au-dessus, flottant à hauteur d'un homme, une silhouette spectrale dont le crâne s'incline lentement vers toi.

Sa voix résonne directement dans ta tête, sans passer par tes oreilles :

« Reste, mortel. Mille ans à attendre, c'est long. Tiens-moi compagnie. »

* [L'affronter pour briser le sortilège]      -> fight_spirit

=== fight_spirit ===
# combat: vengeful_spirit
# flee_to: corridor
# victory_path: spirit_defeated
-> END

=== spirit_defeated ===
La silhouette se déchire dans un cri silencieux et s'évapore en brume bleutée vers la voûte. L'air redevient respirable. Sur l'autel, là où tu n'avais rien vu auparavant, un calice de pierre frémit, encore tiède, plein d'un liquide cuivré.

Tu en bois une gorgée. Une chaleur cuivrée et étrange descend dans tes veines. Tu sens, brièvement, comme une présence amicale derrière toi, mais quand tu te retournes, il n'y a personne.

# add_item: spirit_blood
# heal: 5
# luck_restore

* [Retourner au couloir] -> corridor

// ---------- 5bis. Aile sud du tombeau (Maison de l'Enfer) ----------

=== south_wing ===
La herse cède en grinçant. Tu te courbes pour passer et tu débouches dans une antichambre voûtée, dont les quatre murs portent des bas-reliefs effacés par le temps. Au centre, un brasero éteint dont la cendre est encore tiède — quelqu'un, ou quelque chose, est passé par là il y a peu.

Quatre passages partent dans quatre directions, et aucun ne porte de plaque indiquant où il mène.

À ta gauche, un courant d'air glacé et une odeur de moisi profond. Quelqu'un — ou quelque chose — y respire lentement.

Devant toi, un couloir court qui se dédouble dans des miroirs si nombreux qu'on ne sait plus quel est le vrai.

À ta droite, une voûte basse marquée d'une croix de fer renversée, qui pue le formol et la chair tournée.

Derrière toi, contre toute logique d'orientation, tu entends *ta propre voix* qui chuchote des mots que tu n'as jamais dits.

* {not skeleton_pit} [Suivre le courant d'air à gauche] -> skeleton_pit
* {not mirror_room} [Avancer dans les miroirs] -> mirror_room
* {not lord_vault} [Pousser la porte basse à droite] -> lord_vault
* {not voice_chamber} [Tourner et marcher vers la voix] -> voice_chamber
* [Retourner au couloir principal] -> corridor

=== skeleton_pit ===
Tu descends quelques marches qui s'enfoncent dans le sol — non pas un escalier construit, plutôt un effondrement qu'on aurait apprivoisé. Le courant d'air vient d'une fosse circulaire de quatre mètres de diamètre, encombrée d'ossements blanchis par la cendre.

Au moment où tu mets le pied sur le dernier degré, trois des squelettes les plus entiers se redressent sans un bruit. Un quatrième se recompose sur place, vertèbre après vertèbre. Et la fosse se referme derrière toi avec un grondement de pierre.

{has_necro_oil:
Tu sors prestement l'huile noire de mère Esmé et tu en jettes une goutte au sol. Les squelettes hésitent, se figent une seconde — c'est l'ouverture que tu attendais.
}

* [Te battre dos au mur] -> fight_pit
* {has_necro_oil} [Profiter de l'hésitation et escalader la fosse ★] -> pit_escape

=== fight_pit ===
# combat: pit_skeletons
# victory_path: pit_defeated
-> END

=== pit_defeated ===
Tu écrases le dernier crâne sous ton talon. Le silence revient — un silence qui sent l'os mouillé. Tu fouilles les restes les plus anciens et tu trouves, glissée sous une côte effritée, une bague de fer noire frappée d'un sceau que tu ne reconnais pas. Tu la passes au doigt et tu sens une chaleur sourde, comme si on te tenait la main d'en bas.

# add_item: pit_signet
# luck_bonus: 1

* [Remonter dans l'aile sud] -> south_wing

=== pit_escape ===
Tu te hisses sur un éboulis, attrapes une racine pendant du plafond, et tu t'arraches à la fosse au moment où le quatrième squelette finit de se redresser. Tu retombes essoufflé sur les dalles de l'aile sud.

# damage: 1

* [Souffler un coup et reprendre l'exploration] -> south_wing

=== mirror_room ===
Tu pénètres dans une salle où chaque mur, chaque colonne, chaque dalle au sol est tendu d'un miroir. Tu n'en finis pas de te voir : de face, de profil, de dos, sept fois, dix fois, vingt fois. Et tous les *toi* dans les miroirs ne te regardent pas tous au même endroit.

Au centre de la salle, posée sur un piédestal, une amulette identique à celle que tu cherches. Mortimer a fait construire un leurre.

Trois passages s'ouvrent au fond. Sans repère, tu n'as aucune façon de savoir lequel est réel — sauf à observer les reflets eux-mêmes, ou à laisser faire le hasard.

{has_hunter_compass:
La rose des vents s'agite faiblement dans ta poche. Elle pointe net vers le passage de droite — celui qui te paraissait pourtant le plus illusoire.
}

* {has_hunter_compass} [Suivre la boussole vers la droite] -> mirror_pass_brave
* [Avancer droit sur la sortie centrale] -> mirror_pass_pious
* [Tenter le passage de gauche] -> mirror_pass_pious
* [Briser un miroir avec ton épée pour casser l'illusion] -> mirror_shatter
* [Reculer vers l'antichambre] -> south_wing

=== mirror_pass_brave ===
Tu passes l'arche de droite. Le couloir se rétrécit, les miroirs disparaissent, et tu débouches dans un nouveau passage qui descend doucement. Le sol ici est plus régulier — tu sens que tu as choisi la bonne sortie.

Tu sors dans une voûte basse, plus calme, et un boyau familier te ramène à l'antichambre de l'aile sud.

# luck_restore

* [Retourner à l'antichambre] -> south_wing

=== mirror_pass_pious ===
Tu franchis l'arche. Les miroirs s'épanouissent autour de toi comme des éclats de verre figés. Tu fais trois pas, et puis un seul reflet — celui qui est devant toi — lève un bras au moment où tu ne le lèves pas.

Tu te retournes. Quelque chose te tape sur l'épaule par-derrière, mais quand tu te retournes encore il n'y a rien que toi qui te regardes de partout.

Quand tu sors enfin par une porte qui n'existe pas dans tous les reflets, tu as la tête lourde et le bras qui tremble. Un boyau étroit te ramène à l'antichambre de l'aile sud.

# damage: 3
# luck_test

* [Retourner à l'antichambre] -> south_wing

=== mirror_shatter ===
Tu écrases ton pommeau dans le miroir le plus proche. L'éclat te taillade l'avant-bras, mais quelque chose dans la salle se *décolle*. Le reflet de l'amulette au centre s'éteint d'un coup. Les autres miroirs se brouillent.

Tu vois alors la vraie sortie — celle de gauche, la seule qui n'était pas une boucle. Tu y vas droit, et un boyau étroit te ramène à l'antichambre de l'aile sud.

# damage: 2

* [Retourner à l'antichambre] -> south_wing

=== lord_vault ===
Tu pousses la porte basse marquée de la croix renversée. La salle est plus haute que tu ne l'attendais — une crypte familiale, sept sarcophages alignés contre les murs comme des prêtres en procession arrêtée. La pierre des couvercles a été grattée à l'endroit où les noms s'y trouvaient autrefois.

Au fond, un sarcophage plus simple et plus petit que les autres, marqué d'une initiale unique : *M.*

* [Ouvrir le sarcophage des Mortimer] -> vault_M
* [Fouiller les autres sarcophages] -> vault_others
* [Sortir, l'endroit te glace] -> south_wing

=== vault_M ===
Tu fais coulisser la pierre. Elle pèse, mais elle bouge. Dedans : un cadavre desséché, mal enseveli, qui porte autour du cou un médaillon ouvert où l'on voit encore le visage d'une femme — peut-être la mère de Mortimer, peut-être une fiancée jamais nommée.

Une lettre roulée serrée dans la main morte. Tu la déplies.

« Je n'ai pas tué pour la chair, je n'ai pas tué pour le pouvoir. J'ai tué pour la parole. Il y a une lumière au fond du tombeau, et personne n'ose la voir. Moi je vais. »

Une dernière phrase ajoutée d'une autre main, plus tard :

« Il n'est jamais ressorti. Je l'ai cherché trente ans. — Cassien, prêtre. »

Tu refermes le sarcophage avec un respect que tu n'attendais pas en y entrant.

# luck_bonus: 1

* [Sortir] -> south_wing

=== vault_others ===
Tu fouilles méthodiquement. La plupart des sarcophages sont vides. Dans un, sous un linceul effiloché, un anneau d'argent gravé d'une étoile à six pointes. Tu le glisses dans ta poche. Le grattage des noms commence à faire sens : quelqu'un voulait que cette lignée soit oubliée.

# add_item: silver_seal_ring
# skill_bonus: 1

* [Sortir] -> south_wing

=== voice_chamber ===
Tu marches vers le mur d'où vient la voix — *ta* voix. Le mur n'est qu'un rideau de cendre suspendue qui s'écarte à ton approche. Derrière, une chambre vide, sans torche, sans meuble, où des dizaines de chuchotements se croisent dans l'air comme des oiseaux qui auraient peur de toi.

Tu ne reconnais aucune voix. Et puis, parmi elles, la tienne.

« Si tu reposes l'amulette à sa place, je te laisse remonter. Si tu la prends, je viens avec toi. »

* [Répondre à voix haute : « Mortimer, je viens te chercher »] -> voice_defy
* [Répondre à voix haute : « Je rapporte l'amulette au village »] -> voice_promise
* [Sortir sans répondre, le cœur qui cogne] -> south_wing

=== voice_defy ===
Les chuchotements s'arrêtent un instant. Puis tous, en chœur :

« Bien. »

Tu sens une présence chaude se loger entre tes omoplates — une attention. Mortimer t'a entendu. Tu sors de la chambre avec la nuque qui picote et une certitude étrange : tu n'as plus peur du spectre, mais tu sais maintenant qu'il sait qui tu es.

# skill_bonus: 1
# add_item: mortimer_attention

* [Sortir] -> south_wing

=== voice_promise ===
Les chuchotements deviennent un murmure unique, presque doux.

« Bien. Ramène-la. C'est ce que je voulais entendre. »

Quelque chose en toi se desserre. Tu ne sais pas si c'est la peur, ou un nœud qui aurait toujours été là.

# luck_restore
# heal: 3

* [Sortir] -> south_wing

=== trap_room ===
Tu avances dans un nouveau couloir, plus étroit. Soudain, une dalle s'enfonce sous ton pied avec un déclic sec. Tu te plaques contre le mur. Des lames jaillissent des deux côtés à hauteur de poitrine, balayant l'air à toute vitesse.

Tu tentes ta Chance.

# luck_test

* [Te relever et continuer] -> chamber_vestibule

=== chamber_vestibule ===
Tu pousses la dernière porte, ou plutôt ce qu'il en reste — une charpente vermoulue qui s'effondre presque sous ta main. Au-delà, un vestibule rectangulaire dont les murs portent des fresques effacées : sept silhouettes en procession, chacune tenant un objet que le temps n'a pas laissé deviner.

Au sol, une dalle gravée d'un cercle aux runes mêlées. Tu marches sur le pourtour sans poser le pied au centre — un réflexe de paysan qui sait que les cercles peints au sol sont là pour qu'on les évite.

Au fond du vestibule, une arche, et au-delà : une lumière grise qui pulse lentement, comme un cœur qui aurait oublié son rythme. C'est par là que tu dois passer.

# illustration: final_door
* [Marquer une pause, respirer profondément, fermer les yeux un instant] -> vestibule_pause
* [Pousser l'arche sans réfléchir, avant que le courage ne te quitte] -> final_chamber

=== vestibule_pause ===
Tu t'assois quelques minutes contre la pierre froide. Tu fermes les yeux, tu écoutes le rythme étrange de la lumière au fond. Tu te rappelles le visage du père Cassien, la voix d'Aldwin, le sourire trop sérieux de l'enfant qui te connaissait sans te connaître. Tu te lèves différent — pas plus fort, mais plus net.

# luck_restore
# heal: 2

* [Franchir l'arche] -> final_chamber

=== final_chamber ===
Tu pénètres dans une chambre voûtée, basse et vaste, dont les murs portent encore des fresques effacées par le temps. Au centre, sur un piédestal de marbre veiné de noir, l'amulette repose enfin — pierre verte, sertie d'argent, et qui pulse d'une lumière lente, comme un cœur de chose en sommeil.

Mais avant même que tu n'aies pu faire trois pas, l'air s'épaissit. Une silhouette spectrale se matérialise entre toi et l'amulette, à demi penchée, comme si elle venait d'apparaître au sortir d'un long sommeil. Le sorcier Mortimer en personne, ricanant d'un rire qui n'a plus de gorge depuis longtemps pour le porter.

« Personne ne touche à mon amulette. Pas un fils de fermier en quête de gloire. Pas un seul de tous ceux qui sont venus, ces cinquante dernières années. Et certainement pas toi. »

{has_dead_lord_talisman:
Le talisman gris-cendre brûle dans ta poche, comme s'il reconnaissait son ennemi. Mortimer le voit. Il fronce ses sourcils translucides.
}

{has_protective_charm:
Le charme du sage palpite contre ta poitrine et repousse la peur que le spectre t'envoie. Mortimer plisse les yeux : il l'a reconnu. « Tellor… le lâche. Il vit encore ? »
}

{has_spirit_blood:
La chaleur cuivrée dans tes veines fait reculer le froid spectral d'un pas. Mortimer renifle l'air comme un loup.
}

# chapter: chamber

* [L'affronter en duel]                      -> fight_sorcerer_phase1
* [Tenter de saisir l'amulette et fuir]      -> flee_attempt

=== fight_sorcerer_phase1 ===
# combat: mortimer_spectre_phase1
# victory_path: mortimer_monologue
-> END

=== mortimer_monologue ===
Le spectre vacille sous tes coups, recule contre le piédestal, et soudain — il rit. Un rire bas, presque déçu, qui n'a rien d'un cri d'agonie.

« Je vois. Tu sais frapper. C'est plus que ce que la plupart ont su faire. »

Il se redresse lentement. La silhouette à demi pliée s'étire vers le haut, et tu comprends que tu n'as pas affronté Mortimer — tu as affronté son enveloppe, ce qui restait à la surface après cinquante ans de patience. Ce qui se déplie maintenant est plus grand, plus dense, plus vieux. Les fresques effacées autour de toi se réveillent d'un coup et brillent d'un trait noir.

« Cinquante ans à attendre quelqu'un qui en vaille la peine. Cinquante ans dans le silence, à compter les pas de ceux qui descendaient — et à les renvoyer, un par un, à leurs villages, dans des sacs ou dans des urnes. Tu es le premier à m'avoir fait reculer. Je vais donc te montrer ce que je suis vraiment. »

L'amulette derrière lui pulse plus fort, comme si elle reconnaissait son maître. Le froid revient — pire qu'avant, plus sec, plus précis, comme une lame que l'on tient longtemps avant de frapper.

{has_dead_lord_talisman:
Le talisman gris-cendre s'illumine dans ta poche et brûle plus fort. Mortimer le voit et son sourire se tend.
}
{has_holy_water:
La fiole d'eau bénite chauffe contre ta hanche, prête à se briser au prochain choc. Mortimer la sent, lui aussi, et son regard se voile une seconde.
}
{has_mortimer_attention:
Tu as déjà senti son regard sur toi. Tu sais ce qui vient. Tu poses tes pieds plus solidement.
}

* [Lever ta lame une dernière fois] -> fight_sorcerer_phase2

=== fight_sorcerer_phase2 ===
# combat: mortimer_spectre_phase2
# victory_path: sorcerer_defeated
-> END

=== sorcerer_defeated ===
Le spectre se dissipe en un cri inhumain qui se prolonge longtemps dans la voûte avant de s'éteindre. L'air se réchauffe d'un coup. L'amulette, libérée de son emprise, glisse du piédestal et tombe à tes pieds dans une lueur verte qui te brûle légèrement la main quand tu la ramasses.

Elle est plus lourde qu'elle n'en a l'air. Beaucoup plus.

# add_item: amulet
-> tomb_exit

=== flee_attempt ===
Tu plonges en avant, bras tendu vers l'amulette. Mortimer hurle. Le temps semble se ralentir. Tes doigts effleurent le métal — ou est-ce le métal qui te frôle ?

Tu tentes ta Chance.

# luck_grab_amulette
-> tomb_exit


// ---------- 6. Sortie & épilogue ----------

=== tomb_exit ===
Tu remontes les marches du tombeau plus vite que tu ne les avais descendues, l'amulette serrée contre ta poitrine. Le froid lâche prise marche après marche, et quand tu débouches enfin à l'air libre, le jour t'éblouit. Tu mets longtemps à reconnaître les arbres, les nuages, le bruit du vent dans la forêt.

Tu prends le chemin du retour, marchant longtemps. Les premières heures, tu ne sens rien d'autre que tes jambes et le poids de l'amulette qui bat doucement contre ta poitrine. Tu t'arrêtes près d'un ruisseau pour boire, et tu vois ton reflet : un visage que tu ne reconnais plus tout à fait, plus dur, plus tranchant. Mortimer t'a marqué d'une façon que ton miroir saura un jour te montrer.

L'après-midi se fait soir. Tu retraverses la forêt à l'envers, et chaque endroit que tu reconnais te paraît plus petit qu'à l'aller. La clairière où tu as combattu, le carrefour où tu as choisi, la route où tu as compté tes pas — tout s'est rétréci.

{has_widow_token and has_silver_chain:
Tu touches la chaîne d'argent dans ta bourse. Tomas, le fils de la veuve. Tu sais maintenant comment il est mort, et tu sais qu'elle va le savoir aussi.
}
{has_protective_charm:
Le charme du sage palpite encore contre ta poitrine. Quelque part, sous un grand chêne, Tellor doit avoir senti que tu sors. Tu te demandes s'il sortira un jour, lui aussi.
}

Quand tu vois enfin la fumée du village monter au creux de la combe, le soleil est presque couché.

# chapter: homecoming

* [Avancer vers la place] -> village_return

=== village_return ===
Tu arrives à l'orée du village au moment où le soleil descend. Quelque part dans une maison, un enfant rit pour la première fois depuis longtemps. Maître Aldwin t'attend sur le seuil de la grand-salle, les yeux humides, les mains serrées l'une sur l'autre.

« Tu l'as ? Tu… tu l'as vraiment ? »

L'amulette pulse encore contre ta poitrine, lente, lourde.

* [Remettre l'amulette à Aldwin]                                          -> end_honor
* {has_protective_charm} [La briser à tes pieds, comme Tellor l'a conseillé ★] -> end_destruction
* {has_stolen_loot} [Reculer dans la nuit, l'amulette dans ta bourse ★] -> end_dark
* {has_protective_charm and has_dead_lord_talisman and has_spirit_blood} [Lever l'amulette vers le ciel et invoquer tout ce que tu as appris ★] -> end_transcendence

=== end_honor ===
Tu déposes l'amulette dans la paume tremblante d'Aldwin. Il la regarde un long moment, comme s'il craignait qu'elle ne disparaisse, puis il la serre contre sa poitrine et tu vois, pour la première fois depuis ta naissance, le vieux maître pleurer sans s'en cacher.

La nuit même, il la fait sceller dans une chambre forte sous le temple, gardée par trois prêtres. Au matin, la fontaine de la place coule à nouveau claire. Une semaine plus tard, les épis renaissent. Un mois plus tard, on entend rire à Roncebrune.

{has_silver_chain:
Tu prends le temps, plus tard, de retraverser la place jusqu'au banc de la vieille femme en noir. Tu lui rends la chaîne d'argent sans un mot. Elle la prend du bout des doigts, comme on toucherait une chose vivante. Ses yeux se vident lentement de quinze ans de deuil. Ce soir-là, elle quitte le banc, et on dit qu'elle a fini par dormir.
}

On grave ton nom au-dessus de la porte. Tu refuses, mais on le fait quand même.

FIN — La voie de l'honneur.

# chapter: ending
# outcome: honour
# ending: victory
-> END

=== end_destruction ===
Tu laisses tomber l'amulette sur la pierre du seuil, et tu lèves le pommeau de ton épée. Aldwin pousse un cri qui meurt dans sa gorge. L'amulette se brise en deux dans un éclair vert qui te traverse les os, et le bruit qui en sort, brièvement, ressemble à un soupir d'homme qui n'avait pas respiré depuis cinquante ans.

À l'orée du village, tu aperçois Tellor sous son grand chêne. Il hoche la tête. Il sourit. Il disparaît.

Le lendemain, la fontaine coule à nouveau claire — mais cette fois, on dit qu'elle a un goût d'herbe, et de printemps, et de chose enfin libérée. Roncebrune renaît. Quelqu'un viendra peut-être te demander un jour pourquoi tu as brisé un objet sacré au lieu de le rendre. Tu sauras quoi répondre.

FIN — Tu as brisé le sortilège.

# chapter: ending
# outcome: destruction
# ending: victory
-> END

=== end_dark ===
Tu recules d'un pas dans la pénombre du seuil. Aldwin tend la main, hésitant. Tu recules encore. La nuit te referme dessus comme une porte qui se ferme doucement.

Au matin, on retrouve le vieux maître sur sa chaise, mort, l'amulette n'est plus là, et toi non plus. Quelques années plus tard, à l'est, on dit qu'un nouveau tombeau s'élève au creux d'une colline, gardé par des squelettes en armure rouillée. Nul ne sait qui y règne. Mais ceux qui y sont allés ne reviennent jamais.

Roncebrune meurt enfin, comme elle aurait dû mourir cinquante ans plus tôt.

FIN — Une ombre nouvelle s'allonge sur la forêt.

# chapter: ending
# outcome: dark
# ending: defeat
-> END

=== end_transcendence ===
Tu lèves l'amulette à bout de bras. Le charme du sage palpite dans une main, le talisman du seigneur endormi dans l'autre, et le sang spectral coule, brûlant, dans tes veines. Trois forces qui s'opposaient depuis cinquante ans s'accordent un instant à travers toi.

L'amulette quitte ta paume et s'élève seule au-dessus de ta tête. Elle se met à briller d'un vert très pur, plus clair que la pierre, qui réchauffe le visage des villageois sortis sur le pas de leur porte. Aldwin tombe à genoux. Au loin, dans la forêt, le grand chêne de Tellor frémit ; le vieux sage hoche la tête, sourit, et disparaît sous l'ombre du soir.

L'amulette se dissout dans le ciel en quatre étincelles qui partent vers les quatre points du monde. Mortimer est libéré pour de bon. Roncebrune renaîtra, mais aussi quatre autres villages, ailleurs, dont personne ne saura jamais le nom.

Tu deviens, pour les générations qui suivront, le sorcier-protecteur de la vallée. Le monde a, peut-être, gagné un sage de plus.

FIN — Le passage du sage.

# chapter: ending
# outcome: transcendence
# ending: victory
-> END


// ---------- 7. Mort ----------

=== death ===
Tes forces t'abandonnent. La pierre froide du tombeau accueille ton dos, et le silence te recouvre, doux et indifférent. La dernière chose que tu vois, c'est l'amulette qui pulse encore quelque part, hors d'atteinte, son cœur lent et patient qui battait déjà avant toi et battra longtemps après.

Quelque part, à Roncebrune, un vieil homme attend un voyageur qui ne reviendra plus.

FIN — Ton aventure s'achève ici.

# chapter: ending
# outcome: death
# ending: defeat

-> END
