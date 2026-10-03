//
//  PocketStyle.swift
//  PocketSync
//

import SwiftUI

enum PocketPage {
    case player
    case station
}

enum PocketStyle {
    static let bgColor = Color(red: 0.98, green: 0.93, blue: 0.96)
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.98)
    static let glass = Color.white.opacity(0.68)

    static let bubblePink = Color(red: 0.99, green: 0.40, blue: 0.68)
    static let softPink = Color(red: 0.95, green: 0.77, blue: 0.80)
    static let lavender = Color(red: 0.82, green: 0.81, blue: 0.96)
    static let mint = Color(red: 0.78, green: 0.91, blue: 0.70)
    static let sky = Color(red: 0.77, green: 0.87, blue: 0.98)

    static let border = Color(red: 0.64, green: 0.41, blue: 0.52)
    static let text = Color(red: 0.30, green: 0.17, blue: 0.23)
    static let mutedText = Color(red: 0.56, green: 0.39, blue: 0.48)

    static let panelCorner: CGFloat = 16
    static let screenCorner: CGFloat = 10
    static let cardCorner: CGFloat = 9
    static let buttonCorner: CGFloat = 9

    static let borderWidth: CGFloat = 1.25
    static let thinLine: CGFloat = 0.75

    static let pagePadding: CGFloat = 22
    static let gap: CGFloat = 18
    static let leftWidth: CGFloat = 430
    static let queueHeight: CGFloat = 330
    static let playerHeight: CGFloat = 360
}

extension View {
    @ViewBuilder
    func pocketGlass(cornerRadius: CGFloat = PocketStyle.panelCorner) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial)
        }
    }
}
