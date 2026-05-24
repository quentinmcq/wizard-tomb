## tombTests

Tests unitaires de la logique pure du jeu. Couvrent :

- **`BattleEngineTests`** — résolution d'attaque, jets de Chance offensifs
  et défensifs, fuite, transitions de phases, dommages bonus d'ennemi.
- **`PlayerStateTests`** — `testLuck()` (réussite, échec, consommation de
  Chance), accesseurs `isDead`.
- **`GameSessionLogicTests`** — formatage `runDurationText` (secondes, min,
  heures), grading par score.

### Pourquoi un dossier séparé

Le target principal `tomb` utilise un `PBXFileSystemSynchronizedRootGroup`
qui auto-tracke tout ce qui est sous `tomb/`. Y mettre des fichiers de
test ferait planter la compilation (XCTest n'est pas disponible côté
app). On garde donc les tests dans `tombTests/` à la racine du projet.

### Activer le target dans Xcode

1. **File → New → Target → iOS → Unit Testing Bundle**
2. Nommer le target **`tombTests`**, langue Swift, Target to be Tested = **tomb**
3. Dans le finder du projet, supprimer le dossier `tombTestsTests/` que
   Xcode vient de créer
4. Ajouter le dossier `tombTests/` au projet : clic droit sur le projet →
   **Add Files to "tomb"** → sélectionner `tombTests/` → cocher
   **Create groups** et le target **tombTests** (décocher **tomb**)
5. Dans **Build Phases** du target `tombTests`, ajouter `tomb.app` comme
   dépendance pour que `@testable import tomb` fonctionne
6. ⌘U pour lancer la suite

### Conventions

- Une classe = un type/module testé
- Préfixe `test_` sur chaque méthode
- Pas d'IO réseau / fichiers : pure logique
- Les randoms sont injectés via les paramètres optionnels (`playerRoll`,
  `enemyRoll`, `luckRoll`) — jamais d'appel à `Int.random` dans un test
