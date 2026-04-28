//
//  AppSpacing.swift
//  portfolio_tracker
//
//  Centralized spacing + corner-radius tokens for consistent vertical rhythm.
//

import CoreGraphics

enum AppSpacing {
    /// 2pt — hairline gap between tightly paired elements (e.g. icon + adjacent caption).
    static let xxs: CGFloat = 2
    /// 4pt — tight inline spacing (badge padding, row internal spacing).
    static let xs: CGFloat = 4
    /// 6pt — small gap between label + value in a row.
    static let s: CGFloat = 6
    /// 8pt — default stack spacing for related controls.
    static let m: CGFloat = 8
    /// 12pt — default card internal spacing.
    static let l: CGFloat = 12
    /// 16pt — section padding.
    static let xl: CGFloat = 16
    /// 24pt — major section separation.
    static let xxl: CGFloat = 24
}

enum AppRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
}
