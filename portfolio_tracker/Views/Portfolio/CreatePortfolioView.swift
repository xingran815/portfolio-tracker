//
//  CreatePortfolioView.swift
//  portfolio_tracker
//
//  Multi-section form for creating a new portfolio
//

import SwiftUI

struct CreatePortfolioView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var riskProfile: RiskProfile = .moderate
    @State private var currency: Currency = .cny
    
    @State private var showSettings = false
    @State private var expectedReturn = ""
    @State private var maxDrawdown = ""
    @State private var rebalancingFrequency: RebalancingFrequency = .quarterly
    
    @State private var showTargetAllocation = false
    @State private var targetAllocations: [TargetAllocationData] = []
    
    @State private var showPositions = false
    @State private var positions: [PositionEntryData] = []
    
    var onCreate: (PortfolioConfig) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                settingsSection
                targetAllocationSection
                positionsSection
            }
            .formStyle(.grouped)
            .navigationTitle("新建投资组合")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        createPortfolio()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private var basicInfoSection: some View {
        Section("基本信息") {
            TextField("组合名称", text: $name)
                .textFieldStyle(.roundedBorder)
            
            Picker("风险偏好", selection: $riskProfile) {
                ForEach(RiskProfile.allCases, id: \.self) { profile in
                    Text(profile.displayName).tag(profile)
                }
            }
            
            Picker("货币", selection: $currency) {
                ForEach(Currency.allCases, id: \.self) { curr in
                    Text(curr.displayName).tag(curr)
                }
            }
        }
    }
    
    private var settingsSection: some View {
        DisclosureGroup("设置 (可选)", isExpanded: $showSettings) {
            HStack {
                TextField("预期收益 (%)", text: $expectedReturn)
                    .textFieldStyle(.roundedBorder)
                
                TextField("最大回撤 (%)", text: $maxDrawdown)
                    .textFieldStyle(.roundedBorder)
            }
            
            Picker("调仓频率", selection: $rebalancingFrequency) {
                ForEach(RebalancingFrequency.allCases, id: \.self) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
        }
    }
    
    private var targetAllocationSection: some View {
        DisclosureGroup("目标配置 (可选)", isExpanded: $showTargetAllocation) {
            if targetAllocations.isEmpty {
                Text("暂无目标配置")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(targetAllocations.indices, id: \.self) { index in
                    TargetAllocationRow(
                        symbol: $targetAllocations[index].symbol,
                        percentage: $targetAllocations[index].percentage
                    ) {
                        targetAllocations.remove(at: index)
                    }
                }
                
                if !targetAllocations.isEmpty {
                    let total = targetAllocations.compactMap { $0.allocation?.1 }.reduce(0, +)
                    HStack {
                        Text("合计: \(String(format: "%.1f", total * 100))%")
                            .font(.caption)
                            .foregroundStyle(total > 1.01 || total < 0.99 ? .red : .secondary)
                        Spacer()
                    }
                }
            }
            
            Button(action: {
                targetAllocations.append(TargetAllocationData())
            }) {
                Label("添加目标", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }
    
    private var positionsSection: some View {
        DisclosureGroup("持仓 (可选)", isExpanded: $showPositions) {
            if positions.isEmpty {
                Text("暂无持仓")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(positions.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("持仓 \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        PositionEntryRow(
                            symbol: $positions[index].symbol,
                            name: $positions[index].name,
                            assetType: $positions[index].assetType,
                            market: $positions[index].market,
                            shares: $positions[index].shares,
                            costBasis: $positions[index].costBasis,
                            targetPercentage: .constant("")
                        ) {
                            positions.remove(at: index)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Button(action: {
                positions.append(PositionEntryData())
            }) {
                Label("添加持仓", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }
    
    private func createPortfolio() {
        let positionConfigs = positions.compactMap { $0.positionConfig }
        
        var allocation: [String: Double]? = nil
        if !targetAllocations.isEmpty {
            var dict: [String: Double] = [:]
            for item in targetAllocations {
                if let alloc = item.allocation {
                    dict[alloc.0] = alloc.1
                }
            }
            if !dict.isEmpty {
                allocation = dict
            }
        }
        
        let config = PortfolioConfig(
            name: name.trimmingCharacters(in: .whitespaces),
            riskProfile: riskProfile,
            currency: currency,
            expectedReturn: parsePercentage(expectedReturn),
            maxDrawdown: parsePercentage(maxDrawdown),
            rebalancingFrequency: rebalancingFrequency,
            targetAllocation: allocation,
            positions: positionConfigs
        )
        
        onCreate(config)
        dismiss()
    }
    
    private func parsePercentage(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let num = Double(trimmed) else { return nil }
        return num > 1 ? num / 100.0 : num
    }
}

#Preview {
    CreatePortfolioView { config in
        print("Created: \(config.name)")
    }
}
