//
//  PassageText.swift
//  Rendu du texte d'un passage avec lettrine décorative (première lettre
//  agrandie et dorée). Le texte s'affiche en entier d'un coup : pas d'effet
//  typewriter (trop fatigant en lecture longue).
//

import SwiftUI

struct PassageText: View {
    let text: String
    /// Conservé pour rester compatible avec ContentView : signale aux choix
    /// qu'ils peuvent apparaître. On le bascule à true après un court délai
    /// pour ménager le fade d'entrée et éviter les double-taps.
    @Binding var isComplete: Bool

    @State private var revealTask: Task<Void, Never>? = nil

    /// Petit délai après l'affichage du texte avant d'autoriser les choix,
    /// pour qu'ils ne s'affichent pas en plein milieu de la transition.
    private static let choicesDelayMs = 300

    var body: some View {
        Text(attributedText)
            .font(Theme.body(18))
            .foregroundColor(Theme.ink)
            .lineSpacing(6)
            .kerning(0.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { scheduleReveal() }
            .onChange(of: text) { _, _ in scheduleReveal() }
            .onDisappear { revealTask?.cancel() }
    }

    /// AttributedString avec la première lettre en grand serif doré.
    private var attributedText: AttributedString {
        var attrs = AttributedString(text)
        guard !text.isEmpty else { return attrs }
        let start = attrs.startIndex
        let after = attrs.index(start, offsetByCharacters: 1)
        attrs[start..<after].font = .system(size: 34, weight: .semibold, design: .serif)
        attrs[start..<after].foregroundColor = Theme.oldGold
        attrs[start..<after].baselineOffset = -2
        return attrs
    }

    private func scheduleReveal() {
        revealTask?.cancel()
        isComplete = false
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.choicesDelayMs))
            if Task.isCancelled { return }
            isComplete = true
        }
    }
}
