//
//  SummaryCard.swift
//  portfolio_tracker
//
//  Reusable tinted metric card used across portfolio / rebalancing views.
//

import SwiftUI

struct SummaryCard: View {
    let title: String
    let value: String
    var subtitle: String?
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppFont.rowSubtitle)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(AppFont.cardValue)
                .lineLimit(1)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppColor.cardSurface(tint: color))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)\(subtitle.map { ", \($0)" } ?? "")")
    }
}

#Preview {
    HStack {
        SummaryCard(title: "总资产", value: "$12,345", subtitle: "+2.3%",
                    icon: "dollarsign.circle.fill", color: .blue)
        SummaryCard(title: "盈亏", value: "+$1,234", subtitle: "10.0%",
                    icon: "arrow.up.circle.fill", color: .green)
    }
    .padding()
}
