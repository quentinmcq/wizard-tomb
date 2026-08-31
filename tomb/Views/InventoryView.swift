import SwiftUI

// MARK: - Inventaire (sheet)

struct InventoryView: View {
    @ObservedObject var session: GameSession
    @Environment(\.dismiss) private var dismiss

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

struct ResourceCard: View {
    let gold: Int

    var body: some View {
        HStack(spacing: 10) {
            CoinIcon(size: 18)
            Text("\(gold)")
                .font(Theme.serif(22, weight: .bold))
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
        .parchmentCard()
    }
}

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

    private static var coinImage: UIImage? { Theme.image(named: "coin", ext: "png") }

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
    var isEquipped: Bool = false
    var useDisabledReason: String? = nil
    var onUse: (() -> Void)? = nil
    var onEquip: (() -> Void)? = nil
    var onUnequip: (() -> Void)? = nil
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
                        .foregroundColor(Theme.goldInk)
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
        .parchmentCard(stroke: 0.35, lineWidth: 0.6)
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
            Theme.icon(info.icon, size: 16, color: Theme.goldInk)
                .frame(width: 24, height: 24)
        }
    }

    private static func loadItemImage(itemId: String) -> UIImage? {
        Theme.photo(named: "item_\(itemId)")
    }
}
