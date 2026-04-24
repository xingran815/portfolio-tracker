//
//  PositionEntryRow.swift
//  portfolio_tracker
//
//  Single position input row for portfolio creation
//

import SwiftUI

struct PositionEntryRow: View {
    @Binding var symbol: String
    @Binding var name: String
    @Binding var assetType: AssetType
    @Binding var market: Market
    @Binding var shares: String
    @Binding var costBasis: String
    @Binding var targetPercentage: String
    
    var showTargetAllocation: Bool = false
    var onDelete: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TextField("代码", text: $symbol)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                
                TextField("名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 100)
                
                Picker("类型", selection: $assetType) {
                    ForEach(AssetType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .frame(width: 80)
                
                Picker("市场", selection: $market) {
                    ForEach(Market.allCases, id: \.self) { market in
                        Text(market.displayName).tag(market)
                    }
                }
                .frame(width: 80)
                
                TextField("数量", text: $shares)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                
                TextField("成本", text: $costBasis)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                
                if showTargetAllocation {
                    TextField("目标%", text: $targetPercentage)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
                
                if let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("删除此行")
                }
            }
        }
    }
}

struct TargetAllocationRow: View {
    @Binding var symbol: String
    @Binding var percentage: String
    var onDelete: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("代码", text: $symbol)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            
            TextField("比例 (%)", text: $percentage)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除此分配")
            }
        }
    }
}

struct PositionEntryData {
    var symbol: String = ""
    var name: String = ""
    var assetType: AssetType = .stock
    var market: Market = .us
    var shares: String = ""
    var costBasis: String = ""
    var targetPercentage: String = ""
    
    var isValid: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(shares) != nil && Double(shares)! > 0
    }
    
    var positionConfig: PositionConfig? {
        guard isValid else { return nil }
        return PositionConfig(
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            name: name.isEmpty ? nil : name,
            assetType: assetType,
            market: market,
            shares: Double(shares)!,
            costBasis: Double(costBasis)
        )
    }
}

struct TargetAllocationData {
    var symbol: String = ""
    var percentage: String = ""
    
    var isValid: Bool {
        guard let pct = Double(percentage), pct > 0 else { return false }
        return !symbol.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var allocation: (String, Double)? {
        guard isValid, let pct = Double(percentage) else { return nil }
        let decimal = pct > 1 ? pct / 100.0 : pct
        return (symbol.trimmingCharacters(in: .whitespaces).uppercased(), decimal)
    }
}

#Preview {
    VStack(spacing: 16) {
        PositionEntryRow(
            symbol: .constant("AAPL"),
            name: .constant("Apple Inc."),
            assetType: .constant(.stock),
            market: .constant(.us),
            shares: .constant("100"),
            costBasis: .constant("175.50"),
            targetPercentage: .constant("30"),
            showTargetAllocation: true
        )
        
        TargetAllocationRow(
            symbol: .constant("MSFT"),
            percentage: .constant("25")
        )
    }
    .padding()
}
