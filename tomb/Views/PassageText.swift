import SwiftUI

struct PassageText: View {
    let text: String
    @Binding var isComplete: Bool

    @State private var revealTask: Task<Void, Never>? = nil

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

    private var attributedText: AttributedString {
        var attrs = AttributedString(text)
        guard !text.isEmpty else { return attrs }
        let start = attrs.startIndex
        let after = attrs.index(start, offsetByCharacters: 1)
        attrs[start..<after].font = .system(size: 34, weight: .semibold, design: .serif)
        attrs[start..<after].foregroundColor = Theme.goldInk
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
