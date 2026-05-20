//
//  Theme.swift
//  Palette parchemin/encre + helpers typo pour l'ambiance "vieux bouquin".
//

import SwiftUI
import UIKit
import CoreText

enum Theme {

    // MARK: - Couleurs

    /// Fond clair, papier vieilli.
    static let parchmentLight = Color(red: 0.96, green: 0.91, blue: 0.79)
    /// Cœur du parchemin, légèrement plus saturé.
    static let parchment      = Color(red: 0.93, green: 0.85, blue: 0.69)
    /// Bord d'usure du parchemin, brûlé/foncé.
    static let parchmentDark  = Color(red: 0.78, green: 0.67, blue: 0.47)

    /// Encre principale (presque noire, teintée brune).
    static let ink            = Color(red: 0.18, green: 0.12, blue: 0.08)
    /// Encre secondaire, pour notes en marge.
    static let inkFaded       = Color(red: 0.36, green: 0.26, blue: 0.18)
    /// Rouge sang / cinabre pour Endurance et choses graves.
    static let blood          = Color(red: 0.58, green: 0.13, blue: 0.10)
    /// Bleu encre pour Habileté.
    static let inkBlue        = Color(red: 0.16, green: 0.22, blue: 0.42)
    /// Vert-de-gris pour Chance.
    static let verdigris      = Color(red: 0.27, green: 0.40, blue: 0.30)
    /// Or terne pour pièces et marquages précieux.
    static let oldGold        = Color(red: 0.66, green: 0.49, blue: 0.16)

    // MARK: - Fond du livre

    /// Dégradé radial qui simule la lumière qui tombe au centre du folio
    /// et l'usure plus sombre sur les bords.
    static var pageBackground: some View {
        RadialGradient(
            colors: [parchmentLight, parchment, parchmentDark],
            center: .center,
            startRadius: 60,
            endRadius: 600
        )
        .ignoresSafeArea()
    }

    // MARK: - Typo
    //
    // Polices custom embarquées dans le bundle (cf. INFOPLIST_KEY_UIAppFonts) :
    //   - IM Fell English Roman : corps du texte, esprit "encre sur parchemin"
    //   - IM Fell English Italic : marginalia / italiques
    //   - Cinzel (variable) : titres, HUD, labels small-caps
    // Toutes sous OFL (Open Font License), libres de redistribution.

    /// Corps du texte d'aventure (IM Fell English Roman).
    static func body(_ size: CGFloat = 18) -> Font {
        .custom("IM_FELL_English_Roman", size: size, relativeTo: .body)
    }

    /// Marginalia / italiques (IM Fell English Italic).
    static func margin(_ size: CGFloat = 14) -> Font {
        .custom("IM_FELL_English_Italic", size: size, relativeTo: .callout)
    }

    /// Titre / labels (HUD, fin d'aventure). Cinzel small caps semi-bold.
    ///
    /// Cinzel est embarqué en *variable font* (Cinzel-Variable.ttf). Le
    /// modificateur SwiftUI `.weight(.semibold)` ne sait pas piloter l'axe
    /// `wght` d'un variable font et émet un warning ("Unable to update Font
    /// Descriptor's weight"). On construit donc le descripteur UIKit à la
    /// main en réglant l'axe `wght` à 600 et le réglage typographique
    /// small-caps, puis on emballe dans une `Font` SwiftUI.
    static func display(_ size: CGFloat = 13) -> Font {
        Font(displayUIFont(size: size))
    }

    private static func displayUIFont(size: CGFloat) -> UIFont {
        // 'wght' (FourCC) → identifiant de l'axe de poids des variable fonts.
        let weightAxisTag: UInt32 = 0x77676874

        var descriptor = UIFontDescriptor(name: "Cinzel-Regular", size: size)
            .addingAttributes([
                UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"): [
                    weightAxisTag: 600
                ]
            ])

        // Small caps via feature setting (kLowerCaseType / kLowerCaseSmallCapsSelector).
        descriptor = descriptor.addingAttributes([
            UIFontDescriptor.AttributeName.featureSettings: [
                [
                    UIFontDescriptor.FeatureKey.type: kLowerCaseType,
                    UIFontDescriptor.FeatureKey.selector: kLowerCaseSmallCapsSelector
                ]
            ]
        ])

        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - Modificateurs réutilisables

/// Encadrement façon "carnet en cuir" : bordure double et coins légèrement
/// arrondis. À appliquer sur le HUD ou des panneaux d'effet.
struct LeatherFrame: ViewModifier {
    var tint: Color = Theme.inkFaded

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.parchmentLight.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint.opacity(0.5), lineWidth: 0.8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(tint.opacity(0.25), lineWidth: 0.4)
                    .padding(2)
            )
    }
}

extension View {
    func leatherFrame(tint: Color = Theme.inkFaded) -> some View {
        modifier(LeatherFrame(tint: tint))
    }

    /// Cadre du HUD : parchemin un peu usé, double bordure asymétrique,
    /// vignette discrète aux extrémités. Plus chargé visuellement que
    /// `leatherFrame` mais reste compact pour ne pas voler de place aux
    /// stats.
    func ornamentedHudFrame() -> some View {
        modifier(OrnamentedHudFrame())
    }

    /// Joue le son de clic UI à chaque appui (transition `isPressed`
    /// false → true). À brancher dans le `makeBody` d'un `ButtonStyle`
    /// avec `configuration.isPressed`. Le bouton de choix d'histoire ne
    /// l'utilise pas — il joue le bruit de page tournée à la place.
    func playsButtonTap(isPressed: Bool) -> some View {
        modifier(PlaysButtonTap(isPressed: isPressed))
    }
}

/// Petit modifier qui joue `.buttonTap` quand `isPressed` passe à true.
struct PlaysButtonTap: ViewModifier {
    let isPressed: Bool
    func body(content: Content) -> some View {
        content.onChange(of: isPressed) { _, newValue in
            if newValue {
                AmbientAudio.shared.play(.buttonTap)
            }
        }
    }
}

/// Glyphe d'une stat. Détecte automatiquement si la chaîne fournie est un
/// nom de SF Symbol (ASCII type `heart.fill`) ou un caractère Unicode
/// (⚔, ☥, …) — utile quand aucun SF Symbol ne colle. Pour les glyphes
/// Unicode, on suffixe `U+FE0E` (Variation Selector-15) pour forcer la
/// présentation "texte" plutôt que l'emoji multicolore — sinon le glyphe
/// ignore `.foregroundColor` et reste affiché avec ses couleurs natives
/// d'emoji.
///
/// Cas particulier : `"heart.fill"` est interprété comme l'asset pixel-art
/// custom du jeu (`heart.png`) — voir `Theme.pixelHeart(size:)`. Les
/// autres SF Symbols continuent d'être rendus normalement.
struct StatGlyph: View {
    let icon: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Group {
            if icon.first?.isASCII == false {
                // Un glyphe Unicode rendu comme texte est nettement plus
                // petit visuellement qu'un SF Symbol à la même taille de
                // police (la cap-height d'un glyphe ≪ la zone d'un Image).
                // On compense avec un facteur d'échelle pour aligner ⚔
                // sur les heart.fill / sparkles voisins.
                Text(icon + "\u{FE0E}")
                    .font(.system(size: size * 1.35, weight: .semibold))
                    .foregroundColor(color)
            } else {
                // Ascii : `Theme.icon` intercepte les noms qui correspondent
                // à un PNG du bundle (heart.fill, ability, green_potion…)
                // et retombe sur un SF Symbol sinon.
                Theme.icon(icon, size: size, color: color)
            }
        }
    }
}

extension Theme {

    /// Cache thread-safe d'images pixel-art chargées depuis le bundle.
    /// `NSCache` gère seul la concurrence et la pression mémoire (purge
    /// automatique sous warning), donc on peut l'appeler depuis n'importe
    /// quel thread sans synchroniser à la main.
    private static let bundleImageCache = NSCache<NSString, UIImage>()

    /// Charge `<name>.png` depuis le root du bundle (le projet n'utilise
    /// pas d'Assets.xcassets, les ressources sont placées à plat).
    /// Renvoie nil si l'asset est absent. Cache lazy.
    private static func bundleImage(named name: String) -> UIImage? {
        if let cached = bundleImageCache.object(forKey: name as NSString) {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        bundleImageCache.setObject(img, forKey: name as NSString)
        return img
    }

    /// Image pixel-art arbitraire chargée depuis le bundle. Désactive
    /// l'interpolation (`.interpolation(.none)`) pour garder le rendu net
    /// à l'agrandissement, et bump légèrement la taille (×1.3) pour
    /// matcher visuellement le poids d'un SF Symbol à la même `size`.
    /// Retourne `EmptyView` si l'asset n'existe pas — préférer `Theme.icon`
    /// qui fallback automatiquement sur SF Symbol.
    @ViewBuilder
    static func pixelImage(named name: String, size: CGFloat) -> some View {
        if let img = bundleImage(named: name) {
            Image(uiImage: img)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 1.3, height: size * 1.3)
        } else {
            EmptyView()
        }
    }

    /// Conserve l'API historique : cœur pixel-art via le pipeline générique.
    @ViewBuilder
    static func pixelHeart(size: CGFloat) -> some View {
        pixelImage(named: "heart", size: size)
    }

    /// Rendu unifié pour une icône donnée par nom. Si le nom correspond à
    /// un PNG présent dans le bundle (asset pixel-art custom), on l'utilise.
    /// Sinon, on retombe sur un SF Symbol — ce qui permet aux call sites
    /// existants d'utiliser des noms type `"heart.fill"`, `"sparkles"` ou
    /// d'évoluer vers des assets custom (`"ability"`, `"green_potion"`…)
    /// sans modifier les vues consommatrices.
    @ViewBuilder
    static func icon(_ name: String, size: CGFloat, color: Color) -> some View {
        if bundleImage(named: name) != nil {
            pixelImage(named: name, size: size)
        } else {
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundColor(color)
        }
    }
}

/// Bandeau parchemin "grimoire" pour la barre de statut. Deux couches :
///   1. Fond parchemin un peu sale, avec vignette plus sombre aux bords
///      (gradient radial subtil) pour évoquer du papier qui a jauni.
///   2. Bordure extérieure pleine + bordure intérieure plus fine et plus
///      pâle, décalées de quelques points — ce double trait imite la
///      reliure d'un carnet.
struct OrnamentedHudFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.parchmentLight.opacity(0.75))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [.clear, Theme.ink.opacity(0.08)],
                                center: .center,
                                startRadius: 60,
                                endRadius: 220
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.ink.opacity(0.55), lineWidth: 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Theme.inkFaded.opacity(0.35), lineWidth: 0.4)
                    .padding(2.5)
            )
    }
}

// MARK: - Transition entre passages

extension AnyTransition {
    /// Fade discret entre les passages. Le typewriter qui révèle ensuite
    /// le texte caractère par caractère porte déjà l'essentiel de l'effet
    /// de "tournage de page" — un slide ou une rotation 3D par-dessus
    /// rendrait l'enchaînement chargé et brouillon.
    static var pageTurn: AnyTransition {
        .opacity
    }
}
