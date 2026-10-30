import SwiftUI
import UIKit

enum Theme {
    static let blue = Color(red: 10 / 255, green: 140 / 255, blue: 255 / 255)
    static let lightBlue = Color(red: 108 / 255, green: 195 / 255, blue: 255 / 255)
    static let navy = Color(red: 7 / 255, green: 11 / 255, blue: 26 / 255)
    static let navy2 = Color(red: 14 / 255, green: 28 / 255, blue: 66 / 255)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.38)
    static let cardFill = Color.white.opacity(0.06)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let good = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.13, green: 0.65, blue: 1.0), Color(red: 0.0, green: 0.44, blue: 0.96)],
        startPoint: .top, endPoint: .bottom)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.navy, Theme.navy2], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.blue.opacity(0.30), Color.clear], center: .topTrailing, startRadius: 10, endRadius: 440)
            RadialGradient(colors: [Color(red: 0.25, green: 0.30, blue: 0.95).opacity(0.18), Color.clear], center: .bottomLeading,
                           startRadius: 10, endRadius: 400)
        }
        .ignoresSafeArea()
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

func formatClock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}
