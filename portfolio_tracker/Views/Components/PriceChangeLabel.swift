//
//  PriceChangeLabel.swift
//  portfolio_tracker
//
//  Reusable price change indicator component.
//

import SwiftUI

/// Displays price change with SF-Symbol direction icon + color coding.
struct PriceChangeLabel: View {
    let value: Double
    let percentage: Double
    var currencyCode: String = "USD"

    private var isPositive: Bool { value >= 0 }
    private var isZero: Bool { value == 0 }

    private var color: Color {
        if isZero { return AppColor.neutral }
        return isPositive ? AppColor.gain : AppColor.loss
    }

    private var iconName: String {
        if isZero { return "minus.circle" }
        return isPositive ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    private var directionLabel: String {
        if isZero { return "持平" }
        return isPositive ? "上涨" : "下跌"
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: iconName)
                .font(AppFont.caption)
                .accessibilityHidden(true)
            Text(value.formattedAsCurrency(currencyCode: currencyCode))
                .monospacedDigit()
            Text("(\(percentage.formattedAsPercentage()))")
                .monospacedDigit()
        }
        .font(AppFont.caption)
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(directionLabel) \(value.formattedAsCurrency(currencyCode: currencyCode)), "
            + "\(percentage.formattedAsPercentage())"
        )
    }
}

#Preview {
    VStack(alignment: .leading) {
        PriceChangeLabel(value: 1234.56, percentage: 0.0523)
        PriceChangeLabel(value: -500.00, percentage: -0.025)
        PriceChangeLabel(value: 0, percentage: 0)
    }
    .padding()
}
