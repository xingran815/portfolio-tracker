//
//  RiskBadge.swift
//  portfolio_tracker
//
//  Pill-shaped badge displaying a portfolio's risk profile.
//

import SwiftUI

struct RiskBadge: View {
    let profile: RiskProfile

    private var color: Color {
        switch profile {
        case .conservative: return AppColor.riskConservative
        case .moderate: return AppColor.riskModerate
        case .aggressive: return AppColor.riskAggressive
        }
    }

    var body: some View {
        Text(profile.displayName)
            .font(AppFont.badge)
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, AppSpacing.xxs)
            .background(AppColor.badgeSurface(tint: color))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("风险等级 \(profile.displayName)")
    }
}

#Preview {
    HStack {
        RiskBadge(profile: .conservative)
        RiskBadge(profile: .moderate)
        RiskBadge(profile: .aggressive)
    }
    .padding()
}
