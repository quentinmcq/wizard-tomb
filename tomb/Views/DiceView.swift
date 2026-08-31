import SwiftUI
import SceneKit
import UIKit

// MARK: - Modèle d'un jet en cours d'animation

struct PendingDiceRoll: Equatable {
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

@objc(NonFocusableSCNView)
private final class NonFocusableSCNView: SCNView {
    override var canBecomeFocused: Bool { false }
}

struct Dice3DView: UIViewRepresentable {
    let value: Int
    let tint: Color
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
    }

    // MARK: Construction de la scène

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        let camera = SCNCamera()
        camera.fieldOfView = 32
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.6, 6)
        cameraNode.eulerAngles = SCNVector3(Float(-0.12), 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 380
        ambient.color = UIColor(red: 1.0, green: 0.96, blue: 0.85, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 1000
        key.color = UIColor.white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 5, 0)
        scene.rootNode.addChildNode(keyNode)

        let dieNode = makeDie(targetFace: value, tint: UIColor(tint))
        scene.rootNode.addChildNode(dieNode)

        return scene
    }

    // MARK: Construction du dé

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

    private func orientationForFace(_ face: Int) -> SCNVector3 {
        switch face {
        case 1: return SCNVector3(0, 0, 0)
        case 2: return SCNVector3(0, -Float.pi / 2, 0)
        case 3: return SCNVector3(Float.pi / 2, 0, 0)
        case 4: return SCNVector3(-Float.pi / 2, 0, 0)
        case 5: return SCNVector3(0, Float.pi / 2, 0)
        case 6: return SCNVector3(0, Float.pi, 0)
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
            parchment.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: size, height: size)).fill()

            border.setStroke()
            let rect = CGRect(x: 10, y: 10, width: size - 20, height: size - 20)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
            path.lineWidth = 5
            path.stroke()

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
            try? await Task.sleep(for: .milliseconds(durationMs + 80))
            guard !sumsRevealed else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                sumsRevealed = true
            }
        }
        .onChange(of: revealEarly) { _, new in
            guard new, !sumsRevealed else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                sumsRevealed = true
            }
        }
    }

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
                        .shadow(color: isCrit ? Theme.oldGold.opacity(0.9) : .clear,
                                radius: isCrit ? 6 : 0)
                    if let skill = skillBonus {
                        Text("\(diceSum) + \(skill)")
                            .font(.system(size: 9, weight: .regular, design: .serif))
                            .foregroundColor(Theme.inkFaded)
                            .monospacedDigit()
                    }
                    if showsExtremeChip, isCrit {
                        Text("★ crit ★")
                            .font(Theme.display(8))
                            .foregroundColor(Theme.goldInk)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.5)))
            } else {
                Text("?")
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundColor(tint.opacity(0.35))
            }
        }
    }
}
