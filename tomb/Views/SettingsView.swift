//
//  SettingsView.swift
//  Écran de réglages accessible depuis le menu. Préférences audio
//  persistées via UserDefaults (cf. AmbientAudio), suppression de la
//  sauvegarde en cours, et infos de version.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: GameSession
    @ObservedObject var audio: AmbientAudio
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDeleteSave = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground
                ScrollView {
                    VStack(spacing: 22) {
                        audioSection
                        saveSection
                        aboutSection
                        creditsSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(Theme.ink)
                }
            }
            .confirmationDialog(
                "Effacer la sauvegarde ?",
                isPresented: $confirmDeleteSave,
                titleVisibility: .visible
            ) {
                Button("Effacer la partie en cours", role: .destructive) {
                    session.deleteSave()
                }
                Button("Annuler", role: .cancel) { }
            } message: {
                Text("Tu repartiras à zéro la prochaine fois que tu lanceras le jeu. Cette action ne peut pas être annulée.")
            }
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        SettingsSection(title: "Audio") {
            SettingsToggleRow(
                icon: "speaker.wave.2.fill",
                iconTint: Theme.inkBlue,
                label: "Ambiance sonore",
                hint: "Drone d'ambiance en fond pendant l'aventure.",
                isOn: $audio.ambientEnabled
            )
            SettingsDivider()
            SettingsToggleRow(
                icon: "dice.fill",
                iconTint: Theme.verdigris,
                label: "Effets sonores",
                hint: "Dés, coups, ramassages, jets de Chance.",
                isOn: $audio.effectsEnabled
            )
        }
    }

    // MARK: - Sauvegarde

    private var saveSection: some View {
        SettingsSection(title: "Sauvegarde") {
            Button {
                confirmDeleteSave = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(session.hasSavedGame ? Theme.blood : Theme.inkFaded.opacity(0.6))
                        .font(.system(size: 14))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Effacer la partie en cours")
                            .font(Theme.display(13))
                            .foregroundColor(session.hasSavedGame ? Theme.blood : Theme.inkFaded.opacity(0.6))
                        if !session.hasSavedGame {
                            Text("Aucune sauvegarde à effacer.")
                                .font(Theme.body(12))
                                .italic()
                                .foregroundColor(Theme.inkFaded.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.hasSavedGame)
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

    /// Attribution des assets audio. "Domain of the Specter" est sous CC-BY
    /// 3.0 et requiert le crédit ; les autres morceaux sous CC0 sont cités par
    /// politesse et pour faciliter le suivi de licence.
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

/// Carte parchemin titrée. Le titre flotte en small-caps au-dessus du cadre.
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

private struct SettingsToggleRow: View {
    let icon: String
    let iconTint: Color
    let label: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconTint)
                .font(.system(size: 14))
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
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}
