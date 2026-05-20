//
//  Haptics.swift
//  Wrapper léger autour d'`UIImpactFeedbackGenerator` pour les retours
//  vibratoires en combat. Centralisé pour qu'on puisse changer la
//  granularité (ou désactiver) sans toucher aux call sites.
//

import UIKit

enum Haptics {

    /// Hit standard : tu encaisses ou tu touches un coup normal.
    static func hit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Coup de grâce : enemy à 0 HP, last hit final.
    static func killingBlow() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
    }

    /// Petit feedback léger : miss, ouverture de luck prompt, item utilisé…
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    /// Avertissement (sélection notable, échec critique…).
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
