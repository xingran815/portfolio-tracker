//
//  Typography.swift
//  portfolio_tracker
//
//  Semantic font tokens wrapping system fonts so future dynamic-type audits
//  only need to change one place.
//

import SwiftUI

enum AppFont {
    /// Card titles, prominent numeric values (e.g. summary-card headline value).
    static let cardValue: Font = .title2.weight(.bold)
    /// Section headers in forms / toolbars.
    static let sectionHeader: Font = .headline
    /// Row primary label.
    static let rowTitle: Font = .body
    /// Row secondary label.
    static let rowSubtitle: Font = .subheadline
    /// Numeric cells in tables — apply `.monospacedDigit()` at the call site.
    static let tableCell: Font = .body
    /// Inline help text, subtle captions.
    static let caption: Font = .caption
    /// Badges, compact status pills.
    static let badge: Font = .caption2.weight(.medium)
}
