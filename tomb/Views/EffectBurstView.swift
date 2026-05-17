//
//  EffectBurstView.swift
//  Encart central qui surgit pour annoncer un effet majeur (gain d'objet,
//  bonus permanent...). Spring d'entrée, halo coloré, puis auto-dismiss.
//

import SwiftUI

struct EffectBurst: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String?
    let tint: Color
}

struct EffectBurstView: View {
    let burst: EffectBurst

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: burst.icon)
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(burst.tint)
                .shadow(color: burst.tint.opacity(0.55), radius: 8, x: 0, y: 0)

            Text(burst.title)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)

            if let subtitle = burst.subtitle {
                Text(subtitle)
                    .font(Theme.body(15))
                    .italic()
                    .foregroundColor(Theme.inkFaded)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 30)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(burst.tint.opacity(0.75), lineWidth: 1.6)
        )
        .shadow(color: burst.tint.opacity(0.35), radius: 14, x: 0, y: 6)
        .scaleEffect(appeared ? 1.0 : 0.6)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                appeared = true
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Overlay de jet de Chance narratif

struct NarrativeLuckOverlay: View {
    let roll: NarrativeLuckRoll

    @State private var verdictRevealed = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Test de Chance")
                .font(Theme.display(12))
                .foregroundColor(Theme.inkFaded)

            HStack(spacing: 12) {
                Dice3DView(value: roll.dice.0, tint: Theme.oldGold, durationMs: 1600)
                    .frame(width: 70, height: 70)
                Dice3DView(value: roll.dice.1, tint: Theme.oldGold, durationMs: 1600)
                    .frame(width: 70, height: 70)
            }

            ZStack {
                if verdictRevealed {
                    VStack(spacing: 4) {
                        Text("\(roll.dice.0 + roll.dice.1) \(roll.lucky ? "≤" : ">") \(roll.threshold)")
                            .font(.system(size: 14, design: .serif))
                            .foregroundColor(Theme.inkFaded)
                            .monospacedDigit()
                        Text(roll.lucky ? "Chanceux !" : "Malchanceux")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundColor(roll.lucky ? Theme.oldGold : Theme.blood)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                } else {
                    // Réserve la place pour éviter le saut.
                    Text("Chanceux !")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(.clear)
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 32)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.oldGold.opacity(0.65), lineWidth: 1.5)
        )
        .shadow(color: Theme.oldGold.opacity(0.3), radius: 14, x: 0, y: 6)
        .scaleEffect(appeared ? 1.0 : 0.7)
        .opacity(appeared ? 1.0 : 0)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                appeared = true
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1750))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                verdictRevealed = true
            }
        }
    }
}
