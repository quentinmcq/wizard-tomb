import SwiftUI
import UIKit
import CoreText

enum Theme {
    // MARK: - Couleurs

    static let parchmentLight = Color(red: 0.96, green: 0.91, blue: 0.79)
    static let parchment      = Color(red: 0.93, green: 0.85, blue: 0.69)
    static let parchmentDark  = Color(red: 0.78, green: 0.67, blue: 0.47)

    static let ink            = Color(red: 0.18, green: 0.12, blue: 0.08)
    static let inkFaded       = Color(red: 0.36, green: 0.26, blue: 0.18)
    static let blood          = Color(red: 0.58, green: 0.13, blue: 0.10)
    static let inkBlue        = Color(red: 0.16, green: 0.22, blue: 0.42)
    static let verdigris      = Color(red: 0.27, green: 0.40, blue: 0.30)

    static let oldGold        = Color(red: 0.66, green: 0.49, blue: 0.16)

    static let goldInk        = Color(red: 0.46, green: 0.33, blue: 0.08)

    // MARK: - Fond du livre

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
    //
    // Les trois helpers scalent avec Dynamic Type : `body`/`margin` via le
    // `relativeTo:` de SwiftUI, `display` via `UIFontMetrics` (cf. plus bas).

    static func body(_ size: CGFloat = 18) -> Font {
        .custom("IM_FELL_English_Roman", size: size, relativeTo: .body)
    }

    static func margin(_ size: CGFloat = 14) -> Font {
        .custom("IM_FELL_English_Italic", size: size, relativeTo: .callout)
    }

    static func display(_ size: CGFloat = 13) -> Font {
        Font(displayUIFont(size: size))
    }

    static func serif(_ size: CGFloat,
                      weight: Font.Weight = .regular,
                      maxScale: CGFloat = 1.5) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        let serif = base.fontDescriptor.withDesign(.serif).map {
            UIFont(descriptor: $0, size: size)
        } ?? base
        return Font(UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: serif, maximumPointSize: size * maxScale))
    }

    private static var displayFontCache: [String: UIFont] = [:]

    private static func displayUIFont(size: CGFloat) -> UIFont {
        let category = UITraitCollection.current.preferredContentSizeCategory.rawValue
        let key = "\(size)-\(category)"
        if let cached = displayFontCache[key] { return cached }

        let weightAxisTag: UInt32 = 0x77676874

        var descriptor = UIFontDescriptor(name: "Cinzel-Regular", size: size)
            .addingAttributes([
                UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"): [
                    weightAxisTag: 600
                ]
            ])

        descriptor = descriptor.addingAttributes([
            UIFontDescriptor.AttributeName.featureSettings: [
                [
                    UIFontDescriptor.FeatureKey.type: kLowerCaseType,
                    UIFontDescriptor.FeatureKey.selector: kLowerCaseSmallCapsSelector
                ]
            ]
        ])

        let base = UIFont(descriptor: descriptor, size: size)
        let scaled = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: base, maximumPointSize: size * 1.6)

        displayFontCache[key] = scaled
        return scaled
    }
}

private extension Font.Weight {
    var uiWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
    }
}

// MARK: - Chargement d'images du bundle (cache partagé)

extension Theme {
    /// Cache thread-safe d'images chargées depuis le bundle. `NSCache` gère
    /// seul la concurrence et la pression mémoire (purge automatique sous
    /// warning), donc on peut l'appeler depuis n'importe quel thread sans
    /// synchroniser à la main.
    ///
    /// ⚠️ Toutes les vues doivent passer par ici. Avant, six chargeurs
    /// distincts faisaient `UIImage(contentsOfFile:)` sans cache, dans des
    /// `body` qui se réévaluent en continu (portrait d'ennemi pendant un
    /// shake, fond du menu à chaque sheet…) : chaque frame relisait le JPEG
    /// depuis le disque.
    private static let imageCache = NSCache<NSString, UIImage>()

    private static let missingMarker = UIImage()

    static func image(named name: String, ext: String) -> UIImage? {
        let key = "\(name).\(ext)" as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached === missingMarker ? nil : cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let img = UIImage(contentsOfFile: url.path) else {
            imageCache.setObject(missingMarker, forKey: key)
            return nil
        }
        imageCache.setObject(img, forKey: key)
        return img
    }

    static func photo(named name: String) -> UIImage? {
        image(named: name, ext: "jpg")
    }

    static func strippingPhaseSuffix(_ name: String) -> String? {
        guard let range = name.range(of: #"_phase\d+$"#, options: .regularExpression) else {
            return nil
        }
        return String(name[..<range.lowerBound])
    }

    static func enemyPortrait(_ enemyId: String) -> UIImage? {
        if let img = photo(named: enemyId) { return img }
        if let base = strippingPhaseSuffix(enemyId) { return photo(named: base) }
        return nil
    }

    @ViewBuilder
    static func pixelImage(named name: String, size: CGFloat) -> some View {
        if let img = image(named: name, ext: "png") {
            Image(uiImage: img)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 1.3, height: size * 1.3)
                .alignmentGuide(VerticalAlignment.center) { d in
                    d[VerticalAlignment.center] - 1
                }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    static func icon(_ name: String, size: CGFloat, color: Color) -> some View {
        if let img = image(named: name, ext: "png") {
            Image(uiImage: img)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 1.3, height: size * 1.3)
                .alignmentGuide(VerticalAlignment.center) { d in
                    d[VerticalAlignment.center] - 1
                }
        } else {
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundColor(color)
        }
    }
}

// MARK: - Modificateurs réutilisables

extension View {
    func parchmentCard(cornerRadius: CGFloat = 6,
                       fill: Double = 0.55,
                       stroke: Double = 0.45,
                       lineWidth: CGFloat = 0.8,
                       tint: Color = Theme.inkFaded) -> some View {
        modifier(ParchmentCard(cornerRadius: cornerRadius,
                               fill: fill,
                               stroke: stroke,
                               lineWidth: lineWidth,
                               tint: tint))
    }

    func ornamentedHudFrame() -> some View {
        modifier(OrnamentedHudFrame())
    }

    func playsButtonTap(isPressed: Bool) -> some View {
        modifier(PlaysButtonTap(isPressed: isPressed))
    }

    func minimumTapTarget(_ side: CGFloat = 44) -> some View {
        frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
    }
}

struct ParchmentCard: ViewModifier {
    let cornerRadius: CGFloat
    let fill: Double
    let stroke: Double
    let lineWidth: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.parchmentLight.opacity(fill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint.opacity(stroke), lineWidth: lineWidth)
            )
    }
}

struct PlaysButtonTap: ViewModifier {
    let isPressed: Bool
    func body(content: Content) -> some View {
        content.onChange(of: isPressed) { _, newValue in
            if newValue {
                DispatchQueue.main.async {
                    AmbientAudio.shared.play(.buttonTap)
                }
            }
        }
    }
}

// MARK: - Secousses (shake)

enum Shake {
    static func steps(intensity: CGFloat, heavy: Bool = false) -> [(CGFloat, Double)] {
        if heavy {
            return [(-intensity, 0.06), (intensity, 0.06),
                    (-intensity * 0.7, 0.06), (intensity * 0.7, 0.06),
                    (-intensity * 0.45, 0.06), (intensity * 0.45, 0.06),
                    (0, 0.08)]
        }
        return [(-intensity, 0.05), (intensity, 0.05),
                (-intensity * 0.6, 0.05), (intensity * 0.6, 0.05),
                (0, 0.05)]
    }

    @MainActor
    static func play(_ steps: [(CGFloat, Double)],
                     reduceMotion: Bool,
                     apply: @escaping (CGFloat) -> Void) async {
        guard !reduceMotion else {
            apply(0)
            return
        }
        for (amplitude, duration) in steps {
            withAnimation(.easeInOut(duration: duration)) { apply(amplitude) }
            try? await Task.sleep(for: .seconds(duration))
            if Task.isCancelled {
                withAnimation(.easeOut(duration: 0.1)) { apply(0) }
                return
            }
        }
        withAnimation(.easeOut(duration: 0.05)) { apply(0) }
    }
}

struct StatGlyph: View {
    let icon: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Group {
            if icon.first?.isASCII == false {
                Text(icon + "\u{FE0E}")
                    .font(.system(size: size * 1.35, weight: .semibold))
                    .foregroundColor(color)
            } else {
                Theme.icon(icon, size: size, color: color)
            }
        }
    }
}

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
