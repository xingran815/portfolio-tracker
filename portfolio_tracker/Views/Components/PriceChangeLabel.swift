//
//  PriceChangeLabel.swift
//  portfolio_tracker
//
//  Reusable price change indicator component
//

import SwiftUI

/// Displays price change with color coding
struct PriceChangeLabel: View {
    let value: Double
    let percentage: Double
    var currencyCode: String = "USD"
    
    var isPositive: Bool {
        value >= 0
    }
    
    var color: Color {
        isPositive ? .green : .red
    }
    
    var arrow: String {
        isPositive ? "▲" : "▼"
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Text(arrow)
                .font(.caption)
            Text(value.formattedAsCurrency(currencyCode: currencyCode))
                .monospacedDigit()
            Text("(\(percentage.formattedAsPercentage()))")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(color)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        PriceChangeLabel(value: 1234.56, percentage: 0.0523)
        PriceChangeLabel(value: -500.00, percentage: -0.025)
    }
    .padding()
}
