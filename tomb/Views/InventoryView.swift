//
//  InventoryView.swift
//  Feuille d'inventaire en plein écran : carte « Or », liste d'items avec
//  actions (Utiliser / Équiper / Déséquiper), chips d'état (Équipée /
//  Nouveau / Effet appliqué), et icônes vectorielles utilitaires
//  (`CoinIcon`, `PouchIcon`).
//
//  Extrait de `ContentView.swift` pour lisibilité. Aucune dépendance
//  inversée : tout ce qui est utilisé ici (Theme, GameSession, ItemCatalog…)
//  vit ailleurs.
//

import SwiftUI

// MARK: - Inventaire (sheet)

struct InventoryView: View {
    @ObservedObject var session: GameSession
    @Environment(\.dismiss) private var dismiss

    /// Phrase courte expliquant pourquoi un consommable est inutilisable
    /// dans l'état actuel — affichée sous le bouton grisé.
    private func consumableWasteReason(for effect: ConsumableEffect) -> String {
        switch effect {
        case .heal:        return "Endurance déjà au maximum"
        case .restoreLuck: return "Chance déjà au maximum"
        case .boostSkillNextAttack, .weakenEnemyNextAttack:
            return "À utiliser pendant un combat"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground
                ScrollView {
                    VStack(spacing: 16) {
                        ResourceCard(gold: session.player.gold)
                        if session.player.items.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(Array(session.player.items).sorted(), id: \.self) { itemId in
                                    let info = ItemCatalog.all[itemId]
                                    let isWeapon = info?.weapon != nil
                                    let isEquipped = session.player.equippedWeapon == itemId
                                    // Un consommable n'est proposable que s'il aurait
                                    // un effet réel (pas un soin à PV pleins, pas de
                                    // restore de Chance déjà au max).
                                    let useful = info?.consumable.map(session.isUseful(effect:)) ?? false
                                    InventoryRow(
                                        itemId: itemId,
                                        isEquipped: isEquipped,
                                        useDisabledReason: (info?.consumable != nil && !useful)
                                            ? consumableWasteReason(for: info!.consumable!)
                                            : nil,
                                        onUse: useful
                                            ? { session.useItem(itemId) }
                                            : nil,
                                        onEquip: (isWeapon && !isEquipped)
                                            ? { session.equipWeapon(itemId) }
                                            : nil,
                                        onUnequip: (isWeapon && isEquipped)
                                            ? { session.unequipWeapon() }
                                            : nil,
                                        isUnseen: session.unseenItems.contains(itemId)
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Inventaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(Theme.ink)
                }
            }
            // Repère les items vus : on laisse ~1.5 s au joueur pour
            // apercevoir les chips dorés « Nouveau » avant de les retirer
            // avec un fondu doux. Si le joueur ferme avant, le `dismiss`
            // applique le clear immédiatement (cf. onDisappear).
            .onAppear {
                guard !session.unseenItems.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        session.unseenItems.removeAll()
                    }
                }
            }
            .onDisappear {
                session.unseenItems.removeAll()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Theme.icon("inventory", size: 28, color: Theme.inkFaded.opacity(0.6))
            Text("Ton sac est vide pour l'instant.")
                .font(Theme.body(14))
                .italic()
                .foregroundColor(Theme.inkFaded)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
}

/// Petite carte "Or" en tête d'inventaire. L'or apparaît déjà dans le HUD
/// mais reste affiché ici pour rester visible quand le sac est ouvert.
struct ResourceCard: View {
    let gold: Int

    var body: some View {
        HStack(spacing: 10) {
            CoinIcon(size: 18)
            Text("\(gold)")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(Theme.ink)
                .monospacedDigit()
            Text("pièce\(gold > 1 ? "s" : "") d'or")
                .font(Theme.display(11))
                .foregroundColor(Theme.inkFaded)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
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

/// Bourse à cordons : silhouette de pochette en cuir resserrée par une
/// ficelle, façon "bourse d'or" d'aventurier. Pas de SF Symbol équivalent,
/// donc on la dessine à la main. Utilisée comme icône d'inventaire dans
/// le HUD et dans le récap de fin de partie.
struct PouchIcon: View {
    var size: CGFloat = 14
    var tint: Color = Theme.ink

    var body: some View {
        Canvas { ctx, _ in
            let w = size
            let h = size
            // Bordure / corps : forme arrondie qui s'évase vers le bas,
            // resserrée en haut comme une bourse fermée. Construite à la
            // main avec deux courbes de Bézier symétriques.
            let body = Path { p in
                let neckLeft  = CGPoint(x: w * 0.32, y: h * 0.32)
                let neckRight = CGPoint(x: w * 0.68, y: h * 0.32)
                let leftBelly = CGPoint(x: w * 0.05, y: h * 0.70)
                let bottom    = CGPoint(x: w * 0.50, y: h * 0.98)
                let rightBelly = CGPoint(x: w * 0.95, y: h * 0.70)

                p.move(to: neckLeft)
                p.addQuadCurve(to: leftBelly,
                               control: CGPoint(x: w * 0.02, y: h * 0.45))
                p.addQuadCurve(to: bottom,
                               control: CGPoint(x: w * 0.05, y: h * 1.02))
                p.addQuadCurve(to: rightBelly,
                               control: CGPoint(x: w * 0.95, y: h * 1.02))
                p.addQuadCurve(to: neckRight,
                               control: CGPoint(x: w * 0.98, y: h * 0.45))
                p.closeSubpath()
            }
            ctx.fill(body, with: .color(tint))

            // Cordon : trait horizontal traversant le col, avec deux petits
            // brins qui retombent. Inscrit en couleur "encre" plus claire
            // pour rester lisible sur la pochette.
            let stringColor = tint.opacity(0.55)
            let stringWidth = max(0.8, w * 0.08)
            let neckY = h * 0.30
            let cord = Path { p in
                p.move(to: CGPoint(x: w * 0.22, y: neckY))
                p.addLine(to: CGPoint(x: w * 0.78, y: neckY))
            }
            ctx.stroke(cord, with: .color(stringColor), lineWidth: stringWidth)

            // Deux petits brins qui pendent du nœud central, pour
            // l'identification "ficelle". Court, sec, presque un V.
            let tassels = Path { p in
                let cx = w * 0.50
                p.move(to: CGPoint(x: cx, y: neckY))
                p.addLine(to: CGPoint(x: cx - w * 0.10, y: neckY + h * 0.14))
                p.move(to: CGPoint(x: cx, y: neckY))
                p.addLine(to: CGPoint(x: cx + w * 0.10, y: neckY + h * 0.14))
            }
            ctx.stroke(tassels, with: .color(stringColor), lineWidth: max(0.6, w * 0.06))
        }
        .frame(width: size, height: size)
    }
}

/// Petite pièce d'or — utilise désormais l'asset pixel-art `coin.png` si
/// présent dans le bundle. Sinon, retombe sur un dessin vectoriel
/// (disque doré bordé d'encre + croix discrète) — utile comme garde-fou
/// si l'asset est retiré, l'UI ne se brise pas.
struct CoinIcon: View {
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let img = Self.coinImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                vectorFallback
            }
        }
    }

    /// Cache lazy : `coin.png` chargé une fois depuis le bundle. nil si
    /// l'asset est absent (on retombe alors sur le dessin vectoriel).
    private static let coinImage: UIImage? = {
        guard let url = Bundle.main.url(forResource: "coin", withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()

    private var vectorFallback: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.oldGold,
                            Theme.oldGold.opacity(0.65)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size
                    )
                )
            Circle()
                .stroke(Theme.ink.opacity(0.55), lineWidth: max(0.6, size * 0.06))
            Path { p in
                let inset = size * 0.32
                p.move(to: CGPoint(x: size / 2, y: inset))
                p.addLine(to: CGPoint(x: size / 2, y: size - inset))
                p.move(to: CGPoint(x: inset, y: size / 2))
                p.addLine(to: CGPoint(x: size - inset, y: size / 2))
            }
            .stroke(Theme.ink.opacity(0.55), lineWidth: max(0.5, size * 0.06))
        }
        .frame(width: size, height: size)
    }
}

struct InventoryRow: View {
    let itemId: String
    /// True si c'est l'arme actuellement portée. Affiche un petit chip
    /// « Équipée » à la place du bouton.
    var isEquipped: Bool = false
    /// Si non-nil, affiche un chip explicatif à la place du bouton Utiliser
    /// (ex. « Endurance déjà au maximum »). Indique qu'un consommable
    /// existe mais qu'il serait gâché ici.
    var useDisabledReason: String? = nil
    /// Closure « Utiliser » pour les consommables. Nil = item non
    /// consommable OU à effet nul dans l'état courant.
    var onUse: (() -> Void)? = nil
    /// Closure « Équiper » pour les armes non encore portées. Nil = item
    /// non équipable OU déjà équipé.
    var onEquip: (() -> Void)? = nil
    /// Closure « Déséquiper » — pertinente uniquement sur l'arme actuelle.
    /// Utile surtout pour la lame maudite (perte de Chance) qu'on peut
    /// décider de remiser pour récupérer sa stat.
    var onUnequip: (() -> Void)? = nil
    /// Item ramassé que le joueur n'a pas encore consulté → chip doré
    /// « Nouveau » qui aide à le repérer dans la liste. Repassé à false
    /// dès que la feuille d'inventaire s'affiche (par GameSession).
    var isUnseen: Bool = false

    private var info: ItemCatalog.Info { ItemCatalog.info(itemId) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            itemIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(info.name)
                        .font(Theme.display(13))
                        .foregroundColor(Theme.ink)
                    if isEquipped { equippedChip }
                    if isUnseen { newChip }
                    Spacer(minLength: 0)
                }
                Text(info.description)
                    .font(Theme.body(14))
                    .italic()
                    .foregroundColor(Theme.inkFaded)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let effect = info.effect {
                    Text(effect)
                        .font(Theme.display(10))
                        .foregroundColor(Theme.oldGold)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.oldGold.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Theme.oldGold.opacity(0.35), lineWidth: 0.5)
                        )
                }
                if onUse != nil || onEquip != nil || onUnequip != nil
                    || useDisabledReason != nil || info.bonusAppliedAtPickup {
                    HStack(spacing: 8) {
                        if let onUse {
                            actionButton(label: "Utiliser",
                                         icon: "drop.fill",
                                         tint: Theme.blood,
                                         action: onUse)
                        } else if let reason = useDisabledReason {
                            // Choisit l'icône selon la raison du grisage :
                            //   - Endurance au max → max_life (cœur plein)
                            //   - autres (Chance max, hors combat) → drop.fill
                            // Plus parlant que la goutte par défaut quand on
                            // veut signaler qu'un soin serait gâché.
                            let icon = reason.contains("Endurance")
                                ? "max_life"
                                : "drop.fill"
                            disabledChip(label: reason, icon: icon)
                        } else if info.bonusAppliedAtPickup {
                            disabledChip(label: "Effet appliqué",
                                         icon: "applied_effect")
                        }
                        if let onEquip {
                            actionButton(label: "Équiper",
                                         icon: "equip",
                                         tint: Theme.inkBlue,
                                         action: onEquip)
                        }
                        if let onUnequip {
                            actionButton(label: "Déséquiper",
                                         icon: "unequip",
                                         tint: Theme.inkFaded,
                                         action: onUnequip)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.inkFaded.opacity(0.35), lineWidth: 0.6)
        )
        // Items dont l'effet a été appliqué au pickup (bénédictions, sang
        // spectral…) sont légèrement atténués pour signaler qu'ils sont
        // déjà "joués" — ils restent dans le sac comme trace du parcours.
        .opacity(info.bonusAppliedAtPickup ? 0.78 : 1.0)
    }

    private var equippedChip: some View {
        Text("Équipée")
            .font(Theme.display(9))
            .foregroundColor(Theme.parchmentLight)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.inkBlue.opacity(0.85))
            )
    }

    /// Chip doré « Nouveau » affiché à côté du nom d'un item ramassé que
    /// le joueur n'a pas encore consulté dans cette feuille d'inventaire.
    /// Disparaît à la prochaine ouverture (cf. `markItemsAsSeen()`).
    private var newChip: some View {
        Text("Nouveau")
            .font(Theme.display(9))
            .foregroundColor(Theme.parchmentLight)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.oldGold.opacity(0.9))
            )
    }

    private func actionButton(label: String,
                              icon: String,
                              tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Theme.icon(icon, size: 11, color: Theme.parchmentLight)
                Text(label)
                    .font(Theme.display(11))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(InventoryActionButtonStyle(tint: tint))
    }

    /// Pavé inerte affiché à la place du bouton « Utiliser » quand l'effet
    /// serait gâché (PV ou Chance déjà au max). Visuellement distinct du
    /// bouton : pas de teinte vive, texte gris, pas de tap area.
    private func disabledChip(label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Theme.icon(icon, size: 11, color: Theme.inkFaded.opacity(0.7))
            Text(label)
                .font(Theme.display(11))
        }
        .foregroundColor(Theme.inkFaded.opacity(0.7))
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.parchmentLight.opacity(0.40))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Theme.inkFaded.opacity(0.25), lineWidth: 0.5)
        )
    }

    /// Icône d'item : vraie illustration (photo de musée domaine public)
    /// si elle existe dans le bundle, sinon SF Symbol du catalogue.
    /// La photo est désaturée et teintée parchemin pour s'intégrer.
    @ViewBuilder
    private var itemIcon: some View {
        if let image = Self.loadItemImage(itemId: itemId) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipped()
                .saturation(0)
                .colorMultiply(Theme.parchmentLight)
                .overlay(
                    LinearGradient(
                        colors: [.clear, Theme.parchment.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Theme.inkFaded.opacity(0.4), lineWidth: 0.5)
                )
        } else {
            Theme.icon(info.icon, size: 16, color: Theme.oldGold)
                .frame(width: 24, height: 24)
        }
    }

    private static func loadItemImage(itemId: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "item_\(itemId)",
                                         withExtension: "jpg"),
              let img = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return img
    }
}
