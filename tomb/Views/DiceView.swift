//
//  DiceView.swift
//  Dés 3D animés (SceneKit) pour le combat. Le cube tombe depuis le haut,
//  tourne sur 3 axes pendant la chute, et atterrit sur la face cible avec
//  un petit bounce.
//
//  Textures générées programmatiquement via UIGraphicsImageRenderer (pips
//  façon dé classique sur fond parchemin, couleur des pips paramétrable).
//

import SwiftUI
import SceneKit
import UIKit

// MARK: - Modèle d'un jet en cours d'animation

struct PendingDiceRoll: Equatable {
    /// For an attack roll, we carry both dice values AND the Skill bonus so
    /// the overlay can display the full breakdown (e.g. "7+9 = 16").
    enum Kind: Equatable {
        case attack(playerDice: (Int, Int), playerSkill: Int,
                    enemyDice: (Int, Int),  enemySkill: Int)
        case luck(dice: (Int, Int))

        static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case (.attack(let lpd, let lps, let led, let les),
                  .attack(let rpd, let rps, let red, let res)):
                return lpd == rpd && lps == rps && led == red && les == res
            case (.luck(let l), .luck(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    let id = UUID()
    let kind: Kind

    static func == (lhs: PendingDiceRoll, rhs: PendingDiceRoll) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Vue 3D d'un dé via SceneKit

/// Sous-classe de SCNView qui se déclare invisible au UIFocus engine.
///
/// On NE override PAS `focusItems(in:)` : c'est précisément cet override
/// qui déclenchait le warning iOS « NonFocusableSCNView implements
/// focusItemsInRect: caching for linear focus movement is limited ».
/// UIKit détectait notre selector ObjC et logguait l'avertissement, sans
/// que la valeur retournée par notre override (`[]`) y change quoi que
/// ce soit en pratique. `canBecomeFocused = false` + `accessibilityElementsHidden`
/// suffisent largement pour neutraliser la focus engine sur ces dés.
@objc(NonFocusableSCNView)
private final class NonFocusableSCNView: SCNView {
    override var canBecomeFocused: Bool { false }
}

struct Dice3DView: UIViewRepresentable {
    let value: Int        // 1...6, face qui sera visible à la fin
    let tint: Color       // couleur des pips
    var durationMs: Int = 1300

    func makeUIView(context: Context) -> SCNView {
        let view = NonFocusableSCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.scene = buildScene()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Volontairement vide : pour relancer l'animation, le parent SwiftUI
        // utilise `.id(...)` pour forcer un makeUIView (= nouvelle scène).
    }

    // MARK: Construction de la scène

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        // Caméra cadrée pour voir le dé du dessus de 3/4.
        let camera = SCNCamera()
        camera.fieldOfView = 32
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.6, 6)
        cameraNode.eulerAngles = SCNVector3(Float(-0.12), 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        // Lumière d'ambiance chaude (parchemin).
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 380
        ambient.color = UIColor(red: 1.0, green: 0.96, blue: 0.85, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Lumière directionnelle pour les ombres sur les arêtes du cube.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1000
        key.color = UIColor.white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 5, 0)
        scene.rootNode.addChildNode(keyNode)

        // Le dé.
        let dieNode = makeDie(targetFace: value, tint: UIColor(tint))
        scene.rootNode.addChildNode(dieNode)

        return scene
    }

    // MARK: Construction du dé

    /// Mapping de l'ordre des matériaux SCNBox :
    ///   [0] front (+Z), [1] right (+X), [2] back (-Z),
    ///   [3] left  (-X), [4] top  (+Y),  [5] bottom (-Y)
    /// Convention dé classique : faces opposées somment à 7.
    private static let faceMapping: [Int] = [1, 2, 6, 5, 3, 4]

    private func makeDie(targetFace: Int, tint: UIColor) -> SCNNode {
        let box = SCNBox(width: 1.4, height: 1.4, length: 1.4, chamferRadius: 0.18)
        box.materials = Self.faceMapping.map { face in
            let m = SCNMaterial()
            m.diffuse.contents = faceImage(value: face, tint: tint)
            m.lightingModel = .blinn
            m.roughness.contents = 0.55
            return m
        }

        let node = SCNNode(geometry: box)
        // Départ : haut, légèrement décalé en X pour casser l'alignement, et
        // orientation aléatoire (le dé "tournoie" dans le vide).
        node.position = SCNVector3(
            Float.random(in: -0.4...0.4),
            2.6,
            0
        )
        node.eulerAngles = SCNVector3(
            Float.random(in: -Float.pi ... Float.pi),
            Float.random(in: -Float.pi ... Float.pi),
            Float.random(in: -Float.pi ... Float.pi)
        )

        // Animation séquentielle : (chute + rotation vers cible) puis bounce.
        let target = orientationForFace(targetFace)
        let dur = TimeInterval(durationMs) / 1000.0

        let fall = SCNAction.move(to: SCNVector3(0, 0, 0), duration: dur * 0.85)
        fall.timingMode = .easeIn

        let rotateToTarget = SCNAction.rotateTo(
            x: CGFloat(target.x),
            y: CGFloat(target.y),
            z: CGFloat(target.z),
            duration: dur,
            usesShortestUnitArc: false
        )
        rotateToTarget.timingMode = .easeOut

        let bounceUp = SCNAction.moveBy(x: 0, y: 0.25, z: 0, duration: 0.08)
        bounceUp.timingMode = .easeOut
        let bounceDown = SCNAction.moveBy(x: 0, y: -0.25, z: 0, duration: 0.1)
        bounceDown.timingMode = .easeIn

        node.runAction(SCNAction.sequence([
            SCNAction.group([fall, rotateToTarget]),
            bounceUp,
            bounceDown
        ]))
        return node
    }

    /// Orientation finale (eulerAngles) qui place la face donnée vers la
    /// caméra (axe +Z, ce que regarde le spectateur). Calibré pour le
    /// `faceMapping` ci-dessus.
    private func orientationForFace(_ face: Int) -> SCNVector3 {
        switch face {
        case 1: return SCNVector3(0, 0, 0)                   // front, neutre
        case 2: return SCNVector3(0, -Float.pi / 2, 0)       // right → front
        case 3: return SCNVector3(Float.pi / 2, 0, 0)        // top → front
        case 4: return SCNVector3(-Float.pi / 2, 0, 0)       // bottom → front
        case 5: return SCNVector3(0, Float.pi / 2, 0)        // left → front
        case 6: return SCNVector3(0, Float.pi, 0)            // back → front
        default: return SCNVector3(0, 0, 0)
        }
    }

    // MARK: Génération des textures de face

    private func faceImage(value: Int, tint: UIColor) -> UIImage {
        let size: CGFloat = 256
        let parchment = UIColor(red: 0.96, green: 0.91, blue: 0.79, alpha: 1)
        let border = UIColor(red: 0.36, green: 0.26, blue: 0.18, alpha: 0.55)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            // Fond parchemin
            parchment.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: size, height: size)).fill()

            // Cadre intérieur (effet liseré "cuir")
            border.setStroke()
            let rect = CGRect(x: 10, y: 10, width: size - 20, height: size - 20)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
            path.lineWidth = 5
            path.stroke()

            // Pips
            drawPips(value: value, tint: tint, size: size)
        }
    }

    private func drawPips(value: Int, tint: UIColor, size: CGFloat) {
        let pipRadius = size * 0.085
        let offset    = size * 0.28
        let cx = size / 2
        let cy = size / 2

        let positions: [CGPoint]
        switch value {
        case 1:
            positions = [CGPoint(x: cx, y: cy)]
        case 2:
            positions = [
                CGPoint(x: cx - offset, y: cy - offset),
                CGPoint(x: cx + offset, y: cy + offset)
            ]
        case 3:
            positions = [
                CGPoint(x: cx - offset, y: cy - offset),
                CGPoint(x: cx, y: cy),
                CGPoint(x: cx + offset, y: cy + offset)
            ]
        case 4:
            positions = [
                CGPoint(x: cx - offset, y: cy - offset),
                CGPoint(x: cx + offset, y: cy - offset),
                CGPoint(x: cx - offset, y: cy + offset),
                CGPoint(x: cx + offset, y: cy + offset)
            ]
        case 5:
            positions = [
                CGPoint(x: cx - offset, y: cy - offset),
                CGPoint(x: cx + offset, y: cy - offset),
                CGPoint(x: cx, y: cy),
                CGPoint(x: cx - offset, y: cy + offset),
                CGPoint(x: cx + offset, y: cy + offset)
            ]
        case 6:
            positions = [
                CGPoint(x: cx - offset, y: cy - offset),
                CGPoint(x: cx + offset, y: cy - offset),
                CGPoint(x: cx - offset, y: cy),
                CGPoint(x: cx + offset, y: cy),
                CGPoint(x: cx - offset, y: cy + offset),
                CGPoint(x: cx + offset, y: cy + offset)
            ]
        default:
            positions = []
        }

        // Corps des pips
        tint.setFill()
        for p in positions {
            let pipRect = CGRect(
                x: p.x - pipRadius,
                y: p.y - pipRadius,
                width: pipRadius * 2,
                height: pipRadius * 2
            )
            UIBezierPath(ovalIn: pipRect).fill()
        }

        // Reflet pour effet de relief.
        UIColor.white.withAlphaComponent(0.32).setFill()
        for p in positions {
            let highlightRect = CGRect(
                x: p.x - pipRadius * 0.55,
                y: p.y - pipRadius * 0.55,
                width: pipRadius * 0.65,
                height: pipRadius * 0.65
            )
            UIBezierPath(ovalIn: highlightRect).fill()
        }
    }
}

// MARK: - Overlay des jets dans le combat

struct DiceRollOverlay: View {
    let roll: PendingDiceRoll
    var durationMs: Int = 1300
    /// Quand le parent passe `true`, on révèle immédiatement les totaux
    /// (utilisé pour le tap-to-skip de l'animation). L'animation SceneKit
    /// continue brièvement mais le joueur peut déjà lire le résultat et
    /// les boutons réapparaissent dès la résolution.
    var revealEarly: Bool = false

    @State private var sumsRevealed = false

    var body: some View {
        VStack(spacing: 6) {
            switch roll.kind {
            case .attack(let pDice, let pSkill, let eDice, let eSkill):
                diceRow("TOI",
                        dice: pDice,
                        skillBonus: pSkill,
                        tint: Theme.inkBlue,
                        showsExtremeChip: true)
                Text("vs")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.inkFaded)
                // Le chip "crit / échec" n'a de sens qu'à la première
                // personne. Côté ennemi, "× échec ×" sous ses dés laissait
                // croire au joueur que C'EST LUI qui avait raté son jet —
                // on supprime le chip pour la row ennemie.
                diceRow("ENNEMI",
                        dice: eDice,
                        skillBonus: eSkill,
                        tint: Theme.blood,
                        showsExtremeChip: false)

            case .luck(let dice):
                diceRow("CHANCE",
                        dice: dice,
                        skillBonus: nil,
                        tint: Theme.oldGold,
                        showsExtremeChip: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(0.5), lineWidth: 0.8)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .task {
            // Let the dice roll before revealing the total.
            try? await Task.sleep(for: .milliseconds(durationMs + 80))
            guard !sumsRevealed else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                sumsRevealed = true
            }
        }
        .onChange(of: revealEarly) { _, new in
            // Tap-to-skip déclenché côté parent : on dévoile les totaux
            // immédiatement même si l'animation des dés tourne encore.
            guard new, !sumsRevealed else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                sumsRevealed = true
            }
        }
    }

    /// One row: label on the left, two dice in the middle, total on the
    /// right. If a `skillBonus` is provided (attack roll), the right side
    /// shows the breakdown "diceSum + skill" under the final total.
    /// `showsExtremeChip` détermine si on affiche le chip « ★ crit ★ » /
    /// « × échec × » — désactivé côté ennemi pour ne pas troubler le sens.
    private func diceRow(_ label: String,
                          dice: (Int, Int),
                          skillBonus: Int?,
                          tint: Color,
                          showsExtremeChip: Bool) -> some View {
        let diceSum = dice.0 + dice.1
        let total = diceSum + (skillBonus ?? 0)
        let isCrit = diceSum == 12
        let isFumble = diceSum == 2

        return HStack(spacing: 10) {
            Text(label)
                .font(Theme.display(11))
                .foregroundColor(tint)
                .frame(width: 50, alignment: .leading)

            HStack(spacing: 6) {
                Dice3DView(value: dice.0, tint: tint, durationMs: durationMs)
                    .frame(width: 54, height: 54)
                Dice3DView(value: dice.1, tint: tint, durationMs: durationMs)
                    .frame(width: 54, height: 54)
            }

            totalColumn(diceSum: diceSum,
                        skillBonus: skillBonus,
                        total: total,
                        tint: tint,
                        isCrit: isCrit,
                        isFumble: isFumble,
                        showsExtremeChip: showsExtremeChip)
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        // Les libellés TOI / ENNEMI / CHANCE sont déjà colorés (tint) et
        // suffisent à différencier les rows — pas besoin de fond teinté
        // en plus, qui faisait "carré de couleur" un peu plaqué sur le
        // parchemin.
    }

    private func totalColumn(diceSum: Int,
                              skillBonus: Int?,
                              total: Int,
                              tint: Color,
                              isCrit: Bool,
                              isFumble: Bool,
                              showsExtremeChip: Bool) -> some View {
        ZStack {
            if sumsRevealed {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(total)")
                        .font(.system(size: isCrit ? 26 : 20,
                                      weight: .bold,
                                      design: .serif))
                        .foregroundColor(isFumble ? Theme.inkFaded : tint)
                        .monospacedDigit()
                        // #1 — Halo doré sur 12, gris-éteint sur 2. Le jet
                        // critique reste visuellement marqué dans les deux
                        // rows (utile pour le joueur de voir qu'un crit
                        // ennemi va faire mal).
                        .shadow(color: isCrit ? Theme.oldGold.opacity(0.9) : .clear,
                                radius: isCrit ? 6 : 0)
                    if let skill = skillBonus {
                        Text("\(diceSum) + \(skill)")
                            .font(.system(size: 9, weight: .regular, design: .serif))
                            .foregroundColor(Theme.inkFaded)
                            .monospacedDigit()
                    }
                    // Chip "★ crit ★" sur 12 — uniquement à la première
                    // personne (row "TOI" ou "CHANCE"), côté ennemi on
                    // l'omet pour ne pas confondre le joueur. Le chip
                    // « × échec × » sur 2 a été retiré : il alourdissait
                    // la lecture sans rien apporter (le chiffre 2 +
                    // l'effet visuel "fumble" suffisent à signaler le
                    // résultat).
                    if showsExtremeChip, isCrit {
                        Text("★ crit ★")
                            .font(Theme.display(8))
                            .foregroundColor(Theme.oldGold)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.5)))
            } else {
                // #3 — Placeholder « ? » pendant que les dés tournent. Le
                // joueur sait que quelque chose se calcule, suspense léger.
                Text("?")
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundColor(tint.opacity(0.35))
            }
        }
    }
}
