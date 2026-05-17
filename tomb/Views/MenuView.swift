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

                footer
                    .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    // MARK: - Réglages

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.ink)
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
        if session.hasSavedGame {
            VStack(spacing: 10) {
                MenuPrimaryButton(label: "Reprendre l'aventure",
                                  icon: "play.fill") {
                    audio.start()
                    session.resume()
                }
                MenuSecondaryButton(label: "Nouvelle partie") {
                    audio.start()
                    session.startCharacterCreation()
                }
            }
        } else {
            MenuPrimaryButton(label: "Commencer l'aventure",
                              icon: "play.fill") {
                audio.start()
                session.startCharacterCreation()
            }
        }
    }

    // MARK: - Footer

    /// Numéro de version : passé de 40 % d'opacité à 80 % + drop shadow
    /// pour qu'il reste lisible sur le voile sombre du bas.
    private var footer: some View {
        Text("v0.3 — proto")
            .font(Theme.display(10))
            .foregroundColor(Theme.parchmentLight.opacity(0.8))
            .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
    }
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
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
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
