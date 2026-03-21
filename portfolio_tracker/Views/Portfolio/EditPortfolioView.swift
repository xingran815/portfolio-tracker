//
//  EditPortfolioView.swift
//  portfolio_tracker
//
//  Form for editing an existing portfolio
//

import SwiftUI

struct EditPortfolioView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var riskProfile: RiskProfile
    @State private var currency: Currency
    
    @State private var showSettings = false
    @State private var expectedReturn: String
    @State private var maxDrawdown: String
    @State private var rebalancingFrequency: RebalancingFrequency
    
    @State private var showTargetAllocation = false
    @State private var targetAllocations: [TargetAllocationData]
    
    let portfolio: Portfolio
    var onSave: (Portfolio) -> Void
    
    init(portfolio: Portfolio, onSave: @escaping (Portfolio) -> Void) {
        self.portfolio = portfolio
        self.onSave = onSave
        
        _name = State(initialValue: portfolio.name ?? "")
        _riskProfile = State(initialValue: portfolio.riskProfile)
        _currency = State(initialValue: portfolio.currency)
        
        let returnPct = portfolio.expectedReturn * 100
        _expectedReturn = State(initialValue: returnPct > 0 ? String(format: "%.1f", returnPct) : "")
        
        let drawdownPct = portfolio.maxDrawdown * 100
        _maxDrawdown = State(initialValue: drawdownPct > 0 ? String(format: "%.1f", drawdownPct) : "")
        
        _rebalancingFrequency = State(initialValue: portfolio.rebalancingFrequency)
        
        let allocation = portfolio.targetAllocation
        var allocations: [TargetAllocationData] = []
        for (symbol, pct) in allocation {
            let pctValue = pct > 1 ? pct * 100 : pct
            var data = TargetAllocationData()
            data.symbol = symbol
            data.percentage = String(format: "%.1f", pctValue)
            allocations.append(data)
        }
        _targetAllocations = State(initialValue: allocations)
        _showTargetAllocation = State(initialValue: !allocations.isEmpty)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                settingsSection
                targetAllocationSection
            }
            .formStyle(.grouped)
            .navigationTitle("编辑投资组合")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        savePortfolio()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 450)
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
    
    private func savePortfolio() {
        portfolio.name = name.trimmingCharacters(in: .whitespaces)
        portfolio.riskProfile = riskProfile
        portfolio.currency = currency
        portfolio.expectedReturn = parsePercentage(expectedReturn) ?? 0.08
        portfolio.maxDrawdown = parsePercentage(maxDrawdown) ?? 0.15
        portfolio.rebalancingFrequency = rebalancingFrequency
        portfolio.updatedAt = Date()
        
        var allocation: [String: Double] = [:]
        for item in targetAllocations {
            if let alloc = item.allocation {
                allocation[alloc.0] = alloc.1
            }
        }
        portfolio.targetAllocation = allocation
        
        onSave(portfolio)
        dismiss()
    }
    
    private func parsePercentage(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let num = Double(trimmed) else { return nil }
        return num > 1 ? num / 100.0 : num
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let portfolio = Portfolio(context: context)
    portfolio.name = "测试组合"
    
    return EditPortfolioView(portfolio: portfolio) { _ in
        print("Saved")
    }
}
