//
//  Overlays.swift
//  Vues d'overlay qui se posent par-dessus le contenu principal :
//  transition cinématique de chapitre, mort dramatique, vignette critique
//  d'Endurance, et les utilitaires de feedback visuel (particules de hit,
//  texte flottant ±N, marqueur stamina).
//
//  Extrait de `ContentView.swift` pour ne pas le faire dépasser 2500 lignes.
//

import SwiftUI

// MARK: - Transition cinématique entre chapitres

/// Voile sombre qui apparaît brièvement quand le joueur franchit la
/// frontière d'un chapitre. Trois phases : fade-in (0.8 s) → maintien
/// (~2.8 s) → fade-out (0.8 s). Titre serif doré, fleurons décoratifs et
/// fine ligne or sous le titre. Le tap n'est pas bloqué pendant le hold
/// pour éviter de coincer un joueur impatient ; on appelle `onDismiss`
/// dès la fin de l'animation.
struct ChapterTransitionOverlay: View {
    let chapter: Chapter
    let onDismiss: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var titleScale: CGFloat = 0.96
    @State private var bgOpacity: Double = 0
    @State private var ruleWidth: CGFloat = 0

    var body: some View {
        ZStack {
            // Voile sombre — pas tout à fait noir pour rester organique.
            Color.black.opacity(0.88 * bgOpacity)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                // Fleuron supérieur
                Text("❦")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundColor(Theme.oldGold.opacity(0.85))
                    .opacity(titleOpacity)

                // Titre du chapitre
                Text(chapter.title)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.oldGold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(titleOpacity)
                    .scaleEffect(titleScale)

                // Trait doré sous le titre
                Rectangle()
                    .fill(Theme.oldGold.opacity(0.7))
                    .frame(width: ruleWidth, height: 1)

                // Fleuron inférieur
                Text("❦")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundColor(Theme.oldGold.opacity(0.6))
                    .opacity(titleOpacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissNow() }
        .onAppear {
            // Stinger musical sur l'apparition — 3-note solennel qui se
            // pose en même temps que le titre.
            AmbientAudio.shared.play(.chapterStinger)

            // Phase 1 : fade-in lent du voile + montée douce du titre
            // (0.8 s, ressenti plus posé/cinéma qu'un cut court).
            withAnimation(.easeOut(duration: 0.8)) {
                bgOpacity = 1
                titleOpacity = 1
                titleScale = 1
            }
            // Le trait doré se déroule un peu après, en 1.2 s — souligne
            // le titre comme une plume qui dessine.
            withAnimation(.easeOut(duration: 1.2).delay(0.35)) {
                ruleWidth = 180
            }

            // Phase 2 (maintien) à partir de 0.8 s → 3.6 s = 2.8 s de
            // contemplation, le temps que le stinger résonne et que le
            // titre s'installe. Phase 3 (fade-out) : 0.8 s pour rester
            // dans le même tempo.
            // Total ≈ 4.4 s sans tap, écourtable à tout moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                withAnimation(.easeIn(duration: 0.8)) {
                    bgOpacity = 0
                    titleOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onDismiss()
                }
            }
        }
    }

    /// Permet au joueur d'écourter la transition d'un tap.
    private func dismissNow() {
        withAnimation(.easeIn(duration: 0.3)) {
            bgOpacity = 0
            titleOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Mort cinématique

/// Overlay qui occulte l'écran le temps d'une mort dramatique. Trois
/// temps : voile sang qui inonde l'écran (0.6 s) → résorption vers le
/// noir avec apparition de l'épitaphe (1.0 s) → maintien (~1.8 s) → fade
/// out (0.6 s). Tape pour écourter. À la fin, on appelle `onDismiss` qui
/// révèle l'écran de fin de partie en dessous.
struct DeathCinematicOverlay: View {
    let onDismiss: () -> Void

    @State private var bloodOpacity: Double = 0
    @State private var blackOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 8
    @State private var hasDismissed: Bool = false

    var body: some View {
        ZStack {
            // Voile rouge sang qui s'évanouit ensuite vers le noir
            Theme.blood.opacity(0.85 * bloodOpacity)
                .ignoresSafeArea()

            // Voile noir progressif (prend la suite du voile sang)
            Color.black.opacity(0.92 * blackOpacity)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Theme.icon("epitaph", size: 56, color: Color.white.opacity(0.85))
                    .opacity(titleOpacity)

                Text("Vous tombez.")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundColor(Color.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .opacity(titleOpacity)
                    .offset(y: titleOffset)

                Text("Ici s'achève votre histoire.")
                    .font(.system(size: 14, design: .serif))
                    .italic()
                    .foregroundColor(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .opacity(titleOpacity)
                    .offset(y: titleOffset)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissNow() }
        .onAppear {
            // Stinger d'épitaphe : cloche grave qui frappe pile au moment
            // où l'écran bascule du sang au noir.
            AmbientAudio.shared.play(.epitaph)

            // Phase 1 : voile rouge sang fulgurant
            withAnimation(.easeOut(duration: 0.55)) {
                bloodOpacity = 1
            }
            // Phase 2 : transition rouge → noir + apparition épitaphe
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeInOut(duration: 0.9)) {
                    bloodOpacity = 0
                    blackOpacity = 1
                    titleOpacity = 1
                    titleOffset = 0
                }
            }
            // Phase 3/4 : hold puis fade-out total
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
                guard !hasDismissed else { return }
                withAnimation(.easeIn(duration: 0.6)) {
                    blackOpacity = 0
                    titleOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    guard !hasDismissed else { return }
                    hasDismissed = true
                    onDismiss()
                }
            }
        }
    }

    private func dismissNow() {
        guard !hasDismissed else { return }
        hasDismissed = true
        withAnimation(.easeIn(duration: 0.3)) {
            bloodOpacity = 0
            blackOpacity = 0
            titleOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Vignette critique + utilities

/// Vignette rouge sang qui pulse sur les bords de l'écran quand le joueur
/// passe sous 25% d'Endurance en combat. Stress visuel immédiat sans
/// masquer le contenu central.
struct CriticalHealthVignette: View {
    @State private var pulse: Bool = false

    var body: some View {
        RadialGradient(
            colors: [
                .clear,
                Theme.blood.opacity(pulse ? 0.40 : 0.20)
            ],
            center: .center,
            startRadius: 220,
            endRadius: 520
        )
        .blendMode(.multiply)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Marqueur ±N qui monte et s'éteint sur une jauge quand stamina varie.
/// Utilisé à la fois sur le HUD joueur et la carte d'ennemi pour donner
/// un retour visuel viscéral aux coups.
struct StaminaFloater: Equatable {
    let value: Int
    let id = UUID()
}

/// Petite gerbe de particules qui jaillissent depuis un point quand on
/// reçoit un coup. ~5 éclats projetés perpendiculairement avec un offset
/// random + fade en ~450 ms. Une fois disparus, la view se rend
/// transparente — à instancier avec un `.id()` qui change pour rejouer.
struct HitParticles: View {
    /// Teinte des éclats. Rouge sang pour dégât, doré pour effet bénéfique.
    var tint: Color = Theme.blood

    @State private var progress: CGFloat = 0
    private let count = 5
    private let amplitudes: [CGSize]

    init(tint: Color = Theme.blood, seed: Int = 0) {
        self.tint = tint
        var rng = SystemRandomNumberGenerator()
        let amps: [CGSize] = (0..<5).map { _ in
            let dx = CGFloat(Int.random(in: -22...22, using: &rng))
            let dy = CGFloat(Int.random(in: -20...4, using: &rng))
            return CGSize(width: dx, height: dy)
        }
        self.amplitudes = amps
    }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { idx in
                Circle()
                    .fill(tint.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .offset(
                        x: amplitudes[idx].width * progress,
                        y: amplitudes[idx].height * progress
                    )
                    .opacity(1.0 - Double(progress))
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                progress = 1
            }
        }
    }
}

/// Texte flottant qui apparaît puis monte de quelques points en perdant
/// son opacité. Auto-disparition après ~900 ms.
struct FloatingDamage: View {
    let value: Int

    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 1

    private var tint: Color {
        value < 0 ? Theme.blood : Theme.verdigris
    }

    var body: some View {
        Text(value > 0 ? "+\(value)" : "\(value)")
            .font(.system(size: 18, weight: .bold, design: .serif))
            .foregroundColor(tint)
            .shadow(color: Theme.parchmentLight, radius: 1)
            .monospacedDigit()
            .opacity(opacity)
            .offset(y: offsetY)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9)) {
                    offsetY = -28
                    opacity = 0
                }
            }
            .allowsHitTesting(false)
    }
}
