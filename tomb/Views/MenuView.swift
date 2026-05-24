//
//  MenuView.swift
//  Écran d'accueil dramatisé : gravure de fond + voile sombre, titre en
//  relief, tagline en italique, action principale (Reprendre / Commencer)
//  + action secondaire (Nouvelle partie) si une sauvegarde existe.
//

import SwiftUI

struct MenuView: View {
    @ObservedObject var session: GameSession
    @ObservedObject var audio: AmbientAudio

    @State private var showingSettings = false
    @State private var showingEndings = false
    @State private var showingBestiary = false
    @State private var showingAchievements = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: 50)

                title
                tagline.padding(.top, 26)

                Spacer()

                actions
                    .padding(.horizontal, 40)
                    .padding(.bottom, 28)

                // La version est désormais affichée uniquement dans
                // l'écran Réglages → section "À propos". On retire le
                // footer du menu d'accueil pour éviter le doublon
                // (et d'autant que l'ancien était hardcodé "v0.3 — proto"
                // sans rapport avec la version réelle du bundle).
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Démarre l'ambiance dès l'affichage du menu : le drone doit
                // poser l'atmosphère avant même que le joueur ne clique sur
                // "Commencer". Idempotent côté `AmbientAudio` (guard sur
                // `isPlaying`), donc safe si la vue réapparaît plus tard.
                audio.start()
            }
            .padding(.horizontal, 24)

            settingsButton
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
        .background {
            ZStack {
                Color.black
                if let url = Bundle.main.url(forResource: "menu_cover",
                                              withExtension: "jpg"),
                   let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                }
                LinearGradient(
                    colors: [
                        Theme.parchmentDark.opacity(0.05),
                        Theme.parchmentDark.opacity(0.25),
                        Theme.ink.opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [.clear, Theme.ink.opacity(0.20)],
                    center: .center,
                    startRadius: 220,
                    endRadius: 560
                )
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(session: session, audio: audio)
        }
        .sheet(isPresented: $showingEndings) {
            EndingsView(discovered: session.discoveredEndings)
        }
        .sheet(isPresented: $showingBestiary) {
            BestiaryView(defeated: session.defeatedEnemies)
        }
        .sheet(isPresented: $showingAchievements) {
            AchievementsView(unlocked: session.unlockedAchievements)
        }
    }

    // MARK: - Réglages

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Theme.icon("settings", size: 17, color: Theme.ink)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Theme.parchmentLight.opacity(0.92))
                )
                .overlay(
                    Circle()
                        .stroke(Theme.ink.opacity(0.45), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(SettingsIconButtonStyle())
        .accessibilityLabel("Ouvrir les réglages")
    }

    // MARK: - Titre

    /// Rouge éclairci spécifique au menu : `Theme.blood` est trop foncé
    /// pour ressortir nettement sur la gravure sombre. On garde la même
    /// teinte mais saturée et luminosité plus haute.
    private static let menuBloodBright = Color(red: 0.85, green: 0.22, blue: 0.18)

    private var title: some View {
        VStack(spacing: -2) {
            Text("Le Tombeau")
                .font(.system(size: 52, weight: .bold, design: .serif))
                .foregroundColor(Theme.parchmentLight)
                .shadow(color: .black.opacity(0.95), radius: 10, x: 0, y: 4)
                .shadow(color: Self.menuBloodBright.opacity(0.40), radius: 24, x: 0, y: 0)

            Text("du Sorcier")
                .font(.system(size: 48, weight: .regular, design: .serif))
                .italic()
                .foregroundColor(Self.menuBloodBright)
                .shadow(color: .black.opacity(0.95), radius: 8, x: 0, y: 3)
                .shadow(color: Self.menuBloodBright.opacity(0.65), radius: 22, x: 0, y: 0)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Tagline

    /// Citation d'ambiance qui remplace la pitch méta : on entre dans le
    /// récit dès la page d'accueil. Cartouche d'encre semi-transparent
    /// derrière le texte pour garantir la lisibilité quelle que soit la
    /// gravure de fond.
    private var tagline: some View {
        Text("« Cinquante ans plus tard, le sorcier attend toujours. »")
            .font(.system(size: 16, weight: .semibold, design: .serif))
            .italic()
            .foregroundColor(Theme.parchmentLight)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .shadow(color: .black, radius: 6, x: 0, y: 2)
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.ink.opacity(0.50),
                                Theme.ink.opacity(0.62)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.parchmentLight.opacity(0.18), lineWidth: 0.6)
            )
            .padding(.horizontal, 28)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if session.hasSavedGame {
                MenuPrimaryButton(label: "Reprendre l'aventure",
                                  icon: "start_game") {
                    audio.start()
                    session.resume()
                }
                MenuSecondaryButton(label: "Nouvelle partie") {
                    audio.start()
                    session.startCharacterCreation()
                }
            } else {
                MenuPrimaryButton(label: "Commencer l'aventure",
                                  icon: "start_game") {
                    audio.start()
                    session.startCharacterCreation()
                }
            }
            metaProgressionRow
        }
    }

    /// Petite barre de boutons « Tes aventures » / « Bestiaire » / « Hauts
    /// faits » sous les actions principales. Style discret pour ne pas voler
    /// la vedette à l'action principale mais visibles dès l'accueil.
    private var metaProgressionRow: some View {
        HStack(spacing: 6) {
            MenuTertiaryButton(label: "Aventures",
                               icon: "adventures") {
                showingEndings = true
            }
            MenuTertiaryButton(label: "Bestiaire",
                               icon: "bestiary") {
                showingBestiary = true
            }
            MenuTertiaryButton(label: "Hauts faits",
                               icon: "achievements") {
                showingAchievements = true
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Footer

    // `footer` (numéro de version en bas) supprimé — la version vit
    // désormais dans Réglages → À propos (et reflète le vrai bundle au
    // lieu d'un hardcodé "v0.3 — proto").
}

// MARK: - Boutons du menu

struct MenuPrimaryButton: View {
    let label: String
    let icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    // Theme.icon route automatiquement vers les PNG du bundle
                    // (start_game, restart_game, etc.) ou SF Symbol sinon
                    // (chevron.right, die.face.6.fill).
                    Theme.icon(icon, size: 15, color: Theme.parchmentLight)
                }
                Text(label)
                    .font(Theme.display(15))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPrimaryButtonStyle())
    }
}

struct MenuPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .foregroundColor(Theme.parchmentLight)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.blood.opacity(configuration.isPressed ? 1.0 : 0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.parchmentLight.opacity(0.5), lineWidth: 0.8)
            )
            .shadow(color: Theme.blood.opacity(0.5), radius: 14, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}

struct MenuSecondaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.display(13))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuSecondaryButtonStyle())
    }
}

struct MenuSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Theme.parchmentLight.opacity(0.9))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.ink.opacity(configuration.isPressed ? 0.85 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.parchmentLight.opacity(0.4), lineWidth: 0.6)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}

/// Bouton "tertiaire" du menu : compact, fond parchemin transparent, sert
/// aux accès méta-progression (fins découvertes, bestiaire). Volontairement
/// discret pour ne pas marcher sur les pieds des boutons d'action principaux.
struct MenuTertiaryButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Theme.icon intercepte les PNG du bundle (adventures,
                // bestiary, achievements) et retombe sur SF Symbol sinon.
                Theme.icon(icon, size: 11, color: Theme.parchmentLight.opacity(0.85))
                Text(label)
                    .font(Theme.display(11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuTertiaryButtonStyle())
    }
}

struct MenuTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Texte plus contrasté : ink sombre sur fond clair (avant :
            // parchemin clair sur fond trop transparent — illisible
            // contre certaines zones de l'image de fond).
            .foregroundColor(Theme.ink)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.parchmentLight.opacity(configuration.isPressed ? 0.85 : 0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.inkFaded.opacity(0.45), lineWidth: 0.7)
            )
            .shadow(color: Theme.ink.opacity(0.25), radius: 3, x: 0, y: 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}

/// Style minimaliste pour le bouton roue d'engrenage du menu : pas de
/// background custom (le label porte déjà son cercle parchemin), juste
/// un léger scale au press + le son de clic UI.
private struct SettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .playsButtonTap(isPressed: configuration.isPressed)
    }
}
