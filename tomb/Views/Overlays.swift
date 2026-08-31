import SwiftUI

// MARK: - Transition cinématique entre chapitres

struct ChapterTransitionOverlay: View {
    let chapter: Chapter
    let onDismiss: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var titleScale: CGFloat = 0.96
    @State private var bgOpacity: Double = 0
    @State private var ruleWidth: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.88 * bgOpacity)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("❦")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundColor(Theme.oldGold.opacity(0.85))
                    .opacity(titleOpacity)

                Text(chapter.title)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.oldGold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(titleOpacity)
                    .scaleEffect(titleScale)

                Rectangle()
                    .fill(Theme.oldGold.opacity(0.7))
                    .frame(width: ruleWidth, height: 1)

                Text("❦")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundColor(Theme.oldGold.opacity(0.6))
                    .opacity(titleOpacity)

                Text("Touche pour continuer")
                    .font(Theme.display(10))
                    .tracking(1.4)
                    .foregroundColor(Theme.parchmentDark.opacity(0.75))
                    .opacity(titleOpacity)
                    .padding(.top, 10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissNow() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chapter.title)
        .accessibilityHint("Touche pour continuer.")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            AmbientAudio.shared.play(.chapterStinger)

            withAnimation(.easeOut(duration: 0.8)) {
                bgOpacity = 1
                titleOpacity = 1
                titleScale = 1
            }
            withAnimation(.easeOut(duration: 1.2).delay(0.35)) {
                ruleWidth = 180
            }

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

struct DeathCinematicOverlay: View {
    let onDismiss: () -> Void

    @State private var bloodOpacity: Double = 0
    @State private var blackOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 8
    @State private var hasDismissed: Bool = false

    var body: some View {
        ZStack {
            Theme.blood.opacity(0.85 * bloodOpacity)
                .ignoresSafeArea()

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

                Text("Touche pour continuer")
                    .font(Theme.display(10))
                    .tracking(1.4)
                    .foregroundColor(Color.white.opacity(0.45))
                    .opacity(titleOpacity)
                    .padding(.top, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissNow() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vous tombez. Ici s'achève votre histoire.")
        .accessibilityHint("Touche pour continuer.")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            AmbientAudio.shared.play(.epitaph)

            withAnimation(.easeOut(duration: 0.55)) {
                bloodOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeInOut(duration: 0.9)) {
                    bloodOpacity = 0
                    blackOpacity = 1
                    titleOpacity = 1
                    titleOffset = 0
                }
            }
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

struct CriticalHealthVignette: View {
    @State private var pulse: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            guard !reduceMotion else {
                pulse = true
                return
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct StaminaFloater: Equatable {
    let value: Int
    let id = UUID()
}

struct HitParticles: View {
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .opacity(reduceMotion ? 0 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                progress = 1
            }
        }
    }
}

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
