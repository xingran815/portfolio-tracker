//
//  Palette.swift
//  portfolio_tracker
//
//  Semantic color tokens. Wrap system/semantic colors so dark mode + future
//  accessibility adjustments can happen in one place. Call sites should use
//  these names rather than raw `.green` / `.red`.
//

import SwiftUI

enum AppColor {
    // MARK: Financial semantics

    /// Positive profit / buy order / gain.
    static let gain: Color = .green
    /// Negative profit / sell order / loss.
    static let loss: Color = .red
    /// Neutral / zero change / pending.
    static let neutral: Color = .secondary

    // MARK: Status

    static let info: Color = .blue
    static let warning: Color = .orange
    static let success: Color = .green
    static let danger: Color = .red

    // MARK: Risk profiles

    static let riskConservative: Color = .green
    static let riskModerate: Color = .blue
    static let riskAggressive: Color = .orange

    // MARK: Surfaces

    /// Card background (subtle tinted surface).
    static func cardSurface(tint: Color) -> Color { tint.opacity(0.1) }
    /// Badge background.
    static func badgeSurface(tint: Color) -> Color { tint.opacity(0.2) }
}
