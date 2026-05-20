# Le Tombeau du Sorcier

Aventure dont vous êtes le héros pour iOS, dans la veine des *Défis Fantastiques* (Fighting Fantasy).

Combat tour-par-tour à 2d6 + Habileté, jets de Chance, inventaire, plusieurs fins. Tout le texte est en français ; le moteur tourne sur InkSwift (Ink / inklewriter) wrappé en SwiftUI.

## Lancer le projet

- Xcode 17+ avec SDK iOS 26.5 (le projet cible iOS 26.5+ pour quelques API SwiftUI récentes).
- Ouvrir `tomb.xcodeproj`, sélectionner le scheme `tomb`, choisir un simulateur ou un device, ⌘R.
- Aucune dépendance externe à installer : InkSwift et JXKit sont déjà résolus via Swift Package Manager (cf. `tomb.xcodeproj/project.xcworkspace`).

## Architecture

Les sources Swift sont regroupées par rôle. Le projet Xcode utilise une *synchronized root group* : il suffit de déplacer les fichiers sur disque, Xcode les ramasse automatiquement (pas besoin d'éditer le `.pbxproj`).

```
tomb/
├── App/          TombApp.swift
├── Models/       Models.swift, Battle.swift, EnemyCatalog.swift, ItemCatalog.swift
├── Session/      GameSession.swift
├── Views/        ContentView, MenuView, CharacterCreationView, SettingsView,
│                 BattleView, PassageText, DiceView, EffectBurstView
├── Theme/        Theme.swift
├── Audio/        AmbientAudio.swift, SoundEvents.swift + *.m4a (musiques, SFX)
├── Resources/    adventure.ink, *.ttf (IM Fell, Cinzel)
└── Images/       portraits ennemis, illustrations de scène, menu_cover.jpg
```

| Fichier | Rôle |
|---|---|
| `App/TombApp.swift` | Point d'entrée SwiftUI. Instancie `GameSession` et `AmbientAudio`. |
| `Views/ContentView.swift` | Routeur de l'écran principal : menu, création de personnage, jeu, fin. Anime le tournage de page. |
| `Views/MenuView.swift` | Page d'accueil avec l'illustration de fond et les boutons Reprendre / Nouvelle partie / Réglages. |
| `Views/CharacterCreationView.swift` | Tirage séquentiel des dés (Endurance → Habileté → Chance) puis choix de la difficulté. |
| `Session/GameSession.swift` | Cerveau de la partie : avance la story Ink, applique les tags d'effet, gère sauvegarde / restauration, déclenche les combats et les jets de chance. |
| `Models/Models.swift` | `PlayerState`, `Choice`, `EventMessage`, `Difficulty`, `Chapter`, `CharacterRoll`. |
| `Models/Battle.swift` | Modèle et moteur du combat tour-par-tour (`BattleState`, `BattleEngine`). |
| `Views/BattleView.swift` | UI du combat : carte de l'ennemi, animation des dés, journal, boutons. |
| `Models/EnemyCatalog.swift` | Stats des ennemis, indexés par l'id utilisé dans le tag `# combat:`. |
| `Models/ItemCatalog.swift` | Nom, description et icône des items affichés dans l'inventaire. |
| `Views/DiceView.swift` | Dé 3D en SceneKit et overlay des jets (combat + chance narrative). |
| `Views/PassageText.swift` | Affichage du texte narratif avec révélation progressive. |
| `Views/EffectBurstView.swift` | Notification centrale au gain d'objet ou de bonus permanent. |
| `Views/SettingsView.swift` | Audio, suppression de sauvegarde, crédits. |
| `Theme/Theme.swift` | Palette (parchemin, encre, sang…), polices (IM Fell, Cinzel), cadres (`leatherFrame`, `ornamentedHudFrame`). |
| `Audio/AmbientAudio.swift` | Couche audio : ambiance d'exploration, musique de combat, effets ponctuels. Préférences persistées. |
| `Audio/SoundEvents.swift` | Synthèse procédurale des effets sonores (fallback si le fichier audio n'est pas trouvé). |
| `Resources/adventure.ink` | Toute la narration — knots Ink (identifiants en anglais) avec tags de communication vers Swift. |

### Tags Ink reconnus

Les knots de combat sont vides côté Ink : tout passe par les tags du `# nom: valeur` que `GameSession.applyEffectTags` intercepte.

| Tag | Effet |
|---|---|
| `# combat: <enemy_id>` | Suspend l'histoire, instancie un combat contre l'ennemi du `EnemyCatalog`. |
| `# flee_to: <knot>` | Knot vers lequel fuir pendant ce combat. |
| `# victory_path: <knot>` | Knot où sauter en cas de victoire. |
| `# damage: <n>` | Retire `n` points d'Endurance (déclenche `mort` si ≤ 0). |
| `# heal: <n>` | Restaure `n` points d'Endurance (capé au max). |
| `# stamina_bonus: <n>` | Augmente l'Endurance max ET courante (bonus permanent). |
| `# skill_bonus: <n>` | Augmente l'Habileté permanente. |
| `# luck_bonus: <n>` | Augmente la Chance permanente. |
| `# luck_restore` | Remet la Chance à son maximum. |
| `# spend_gold: <n>` | Retire `n` pièces. La VAR Ink `gold` est resynchro pour les choix conditionnels payants. |
| `# gain_gold: <n>` | Ajoute `n` pièces. |
| `# add_item: <id>` | Ajoute l'item au sac et set `has_<id> = 1` côté Ink. |
| `# luck_test` | Pause sur un bouton « Tenter ma Chance » ; -4 Endurance si malchanceux. |
| `# luck_test_book` | Variante : -4 si malchanceux, Chance restaurée si chanceux. |
| `# luck_grab_amulette` | Cas spécial Mortimer (chanceux = amulette, malchanceux = mort). |
| `# illustration: <name>` | Affiche `illustration_<name>.jpg` (ou `<name>.jpg`) en pleine page avant le passage suivant. |
| `# chapter: <id>` | Marque le chapitre courant (utilisé par le récap de fin). |
| `# outcome: <id>` | Identifie l'issue (utilisé par le score). |
| `# ending: victory\|defeat` | Joue le jingle approprié. |

### Éditer l'aventure (hot-reload en Debug)

En Debug, `GameSession.readAdventureSource` mire le `adventure.ink` du bundle dans `Documents/adventure.ink`, en rafraîchissant la copie quand le bundle est plus récent. Tu peux ouvrir le fichier dans Documents pendant que l'app tourne, et un « Nouvelle partie » suffit à recharger le texte sans rebuilder Xcode.

En Release, le fichier est lu directement depuis le bundle.

### Sauvegarde

`UserDefaults`, clé `tomb.save.v11`. Stocke le `storyState` d'InkSwift, le `PlayerState`, les choix courants, l'historique des messages et le score. La clé est versionnée : à chaque changement de format (renommage massif de knots Ink, refonte de `PlayerState`…) on l'incrémente pour invalider proprement les anciennes saves.

## Crédits

### Audio
- **Musique de combat** — « Domain of the Specter » par HitCtrl (CC-BY 3.0, [OpenGameArt](https://opengameart.org))
- **Ambiance donjon** — « Loopable Dungeon Ambience » (CC0, OpenGameArt)
- **Effets sonores** — « 80 CC0 RPG SFX » (CC0, OpenGameArt)

### Visuel
- **Portraits de monstres** — illustrations issues de la série *Fighting Fantasy* (Steve Jackson & Ian Livingstone, Puffin / Penguin Books) et de leurs illustrateurs — Russ Nicholson, Iain McCaig, Alan Langford, Bob Harvey et al. Utilisées comme hommage non commercial dans un projet personnel ; à retirer si l'app sort un jour de ce cadre.
- **Illustrations de scène** — gravures domaine public de Gustave Doré (*Divine Comédie*, 1861), Hans Holbein le Jeune (*Danse macabre*, 1538), Giovanni Battista Piranesi (*Carceri d'Invenzione*, 1750), via Wikimedia Commons.
- **Portrait NPC (Tellor)** — illustration originale réalisée pour le projet, dans le style des éditions Spook's Books.

### Texte & code
- Aventure originale écrite pour le projet, inspirée des *Défis Fantastiques* (Steve Jackson & Ian Livingstone) et plus particulièrement de *La Nuit du Loup-Garou*, *La Cité des Voleurs* et *La Maison de l'Enfer*.
- Moteur narratif : [InkSwift](https://github.com/maarten-engels/InkSwift) (Maarten Engels) qui wrappe [inkjs](https://github.com/y-lohse/inkjs) via JXKit.
- Polices : *IM Fell English* (Igino Marini) et *Cinzel* (Natanael Gama), sous Open Font License.

## Licence

Le code est personnel et non publié. Les assets tiers conservent leurs licences respectives (voir crédits). Le contenu Fighting Fantasy n'est pas redistribué publiquement.
