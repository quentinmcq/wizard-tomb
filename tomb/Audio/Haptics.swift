import UIKit

enum Haptics {
    static func hit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func killingBlow() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
