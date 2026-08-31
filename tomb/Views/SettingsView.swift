import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: GameSession
    @ObservedObject var audio: AmbientAudio
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground
                ScrollView {
                    VStack(spacing: 22) {
                        audioSection
                        if session.hasSavedGame { saveSection }
                        aboutSection
                        creditsSection
                    }
                    .padding(20)
                }
            }
            .alert("Effacer la sauvegarde ?", isPresented: $showingDeleteConfirm) {
                Button("Annuler", role: .cancel) {}
                Button("Effacer", role: .destructive) {
                    session.deleteSave()
                    dismiss()
                }
            } message: {
                Text("La partie en cours sera définitivement perdue. Tes hauts faits, ton bestiaire et les fins déjà découvertes sont conservés.")
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(Theme.ink)
                }
            }
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        SettingsSection(title: "Audio") {
            SettingsAudioRow(
                icon: "sound",
                iconTint: Theme.inkBlue,
                label: "Ambiance sonore",
                hint: "Musique d'ambiance pendant l'aventure.",
                isOn: $audio.ambientEnabled,
                volume: $audio.ambientVolume
            )
            SettingsDivider()
            SettingsAudioRow(
                icon: "sound_effect",
                iconTint: Theme.verdigris,
                label: "Effets sonores",
                hint: "Dés, coups, jets de dés, etc.",
                isOn: $audio.effectsEnabled,
                volume: $audio.effectsVolume
            )
        }
    }

    // MARK: - Sauvegarde

    private var saveSection: some View {
        SettingsSection(title: "Sauvegarde") {
            Button {
                showingDeleteConfirm = true
            } label: {
                HStack(spacing: 12) {
                    Theme.icon("delete_save", size: 14, color: Theme.blood)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Effacer la sauvegarde")
                            .font(Theme.display(13))
                            .foregroundColor(Theme.blood)
                        Text("La partie en cours sera perdue. La méta-progression est conservée.")
                            .font(Theme.body(12))
                            .italic()
                            .foregroundColor(Theme.inkFaded)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre une confirmation avant d'effacer.")
        }
    }

    // MARK: - À propos

    private var aboutSection: some View {
        SettingsSection(title: "À propos") {
            Text("Version \(appVersionString)")
                .font(Theme.display(11))
                .foregroundColor(Theme.inkFaded)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (build \(build))"
    }

    // MARK: - Crédits

    private var creditsSection: some View {
        SettingsSection(title: "Crédits") {
            VStack(alignment: .leading, spacing: 8) {
                creditLine(label: "Musique de combat",
                           value: "« Domain of the Specter » par HitCtrl (CC-BY 3.0, OpenGameArt)")
                creditLine(label: "Ambiance donjon",
                           value: "« Loopable Dungeon Ambience » (CC0, OpenGameArt)")
                creditLine(label: "Effets sonores",
                           value: "« 80 CC0 RPG SFX » (CC0, OpenGameArt)")
                creditLine(label: "Portraits de monstres",
                           value: "Illustrations issues de la série Fighting Fantasy (Steve Jackson & Ian Livingstone, Puffin / Penguin Books) et de leurs illustrateurs — Russ Nicholson, Iain McCaig, Alan Langford et al. Usage hommage non commercial.")
                creditLine(label: "Icônes pixel-art",
                           value: "Caio Carlos of the Clockwork Raven — Additional Art Assets (License User-side, usage commercial autorisé sans crédit obligatoire).")
                creditLine(label: "Polices",
                           value: "IM Fell English & Cinzel (Open Font License)")
                creditLine(label: "Moteur narratif",
                           value: "InkSwift par Maarten Engels (inklewriter / Ink)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func creditLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.display(10))
                .foregroundColor(Theme.inkFaded)
            Text(value)
                .font(Theme.body(12))
                .italic()
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Section / Row réutilisables

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.display(11))
                .foregroundColor(Theme.inkFaded)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.parchmentLight.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.inkFaded.opacity(0.45), lineWidth: 0.8)
            )
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.inkFaded.opacity(0.25))
            .frame(height: 0.6)
            .padding(.horizontal, 14)
    }
}

private struct SettingsAudioRow: View {
    let icon: String
    let iconTint: Color
    let label: String
    let hint: String
    @Binding var isOn: Bool
    @Binding var volume: Float

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Theme.icon(icon, size: 14, color: iconTint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Theme.display(13))
                        .foregroundColor(Theme.ink)
                    Text(hint)
                        .font(Theme.body(12))
                        .italic()
                        .foregroundColor(Theme.inkFaded)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(Theme.blood)
            }

            HStack(spacing: 12) {
                Color.clear.frame(width: 22, height: 1)
                Slider(value: $volume, in: 0...1)
                    .tint(iconTint)
                    .disabled(!isOn)
                    .opacity(isOn ? 1.0 : 0.4)
                Text("\(Int(volume * 100)) %")
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .foregroundColor(isOn ? Theme.ink : Theme.inkFaded.opacity(0.5))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

