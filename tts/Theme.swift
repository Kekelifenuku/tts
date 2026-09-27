//
//  Theme.swift
//  tts
//
//  Shared colors, gradients and reusable styling.
//

import SwiftUI
import UIKit

enum AppTheme {
    /// Brand gradient used for the primary play button, progress and accents.
    static let gradient = LinearGradient(
        colors: [
            Color(red: 0.35, green: 0.30, blue: 0.92),
            Color(red: 0.62, green: 0.32, blue: 0.93)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accent = Color(red: 0.42, green: 0.32, blue: 0.92)

    /// Highlight used behind the word currently being spoken.
    static let highlight = Color(red: 1.0, green: 0.85, blue: 0.30)

    /// Soft full-screen background that fades the accent into the system background.
    static var background: some View {
        LinearGradient(
            colors: [accent.opacity(0.16), Color(uiColor: .systemGroupedBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Rounded, elevated container used to group content into cards.
private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}
