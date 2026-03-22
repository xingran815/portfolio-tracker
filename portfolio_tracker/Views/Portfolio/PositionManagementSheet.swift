//
//  PositionManagementSheet.swift
//  portfolio_tracker
//
//  Unified sheet for Add/Buy/Sell/Edit position operations
//

import SwiftUI

enum PositionManagementMode {
    case add
    case buyMore
    case sell
    case edit
    
    var title: String {
        switch self {
        case .add: return "添加持仓"
        case .buyMore: return "加仓"
        case .sell: return "卖出"
        case .edit: return "编辑持仓"
        }
    }
    
    var confirmButton: String {
        switch self {
        case .add, .buyMore: return "确认买入"
        case .sell: return "确认卖出"
        case .edit: return "保存"
        }
    }
}

struct PositionManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let mode: PositionManagementMode
    let viewModel: PortfolioDetailViewModel
    let existingPosition: Position?
    
    @State private var symbol = ""
    @State private var name = ""
    @State private var assetType: AssetType = .stock
    @State private var market: Market = .us
    @State private var shares = ""
    @State private var price = ""
    @State private var fees = ""
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    init(mode: PositionManagementMode, viewModel: PortfolioDetailViewModel, existingPosition: Position? = nil) {
        self.mode = mode
        self.viewModel = viewModel
        self.existingPosition = existingPosition
        
        if let position = existingPosition {
            _symbol = State(initialValue: position.symbol ?? "")
            _name = State(initialValue: position.name ?? "")
            _assetType = State(initialValue: position.assetType)
            _market = State(initialValue: position.market)
            if mode == .edit {
                _shares = State(initialValue: String(format: "%.2f", position.shares))
                _price = State(initialValue: String(format: "%.2f", position.costBasis))
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                
                transactionSection
                
                if mode == .sell || mode == .buyMore {
                    currentInfoSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.confirmButton) {
                        performAction()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .frame(minWidth: 450, minHeight: 400)
    }
    
    private var basicInfoSection: some View {
        Section("基本信息") {
            TextField("代码 (如 AAPL)", text: $symbol)
                .textFieldStyle(.roundedBorder)
                .disabled(mode != .add)
            
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .disabled(mode == .buyMore || mode == .sell)
            
            Picker("资产类型", selection: $assetType) {
                ForEach(AssetType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .disabled(mode == .buyMore || mode == .sell)
            
            Picker("市场", selection: $market) {
                ForEach(Market.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .disabled(mode == .buyMore || mode == .sell)
        }
    }
    
    private var transactionSection: some View {
        Section(mode == .edit ? "持仓信息" : "交易信息") {
            HStack {
                TextField(mode == .sell ? "卖出数量" : "数量", text: $shares)
                    .textFieldStyle(.roundedBorder)
                
                if mode == .sell, let position = existingPosition {
                    Text("/ \(String(format: "%.2f", position.shares))")
                        .foregroundStyle(.secondary)
                }
            }
            
            TextField(mode == .sell ? "卖出价格" : "成本价", text: $price)
                .textFieldStyle(.roundedBorder)
            
            TextField("手续费 (可选)", text: $fees)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    private var currentInfoSection: some View {
        Section {
            if let position = existingPosition {
                LabeledContent("当前持有", value: String(format: "%.2f 股", position.shares))
                LabeledContent("当前成本", value: String(format: "%.2f", position.costBasis))
                
                if mode == .buyMore, let sharesNum = Double(shares), let priceNum = Double(price) {
                    let newTotalShares = position.shares + sharesNum
                    let newAvgCost = ((position.shares * position.costBasis) + (sharesNum * priceNum)) / newTotalShares
                    LabeledContent("加仓后平均成本", value: String(format: "%.2f", newAvgCost))
                        .foregroundStyle(.blue)
                }
                
                if mode == .sell {
                    if let sharesNum = Double(shares), let priceNum = Double(price), sharesNum <= position.shares {
                        let remaining = position.shares - sharesNum
                        let gainLoss = (priceNum - position.costBasis) * sharesNum
                        LabeledContent("剩余股数", value: String(format: "%.2f", remaining))
                        LabeledContent("预估盈亏", value: String(format: "%.2f", gainLoss))
                            .foregroundStyle(gainLoss >= 0 ? .green : .red)
                    }
                }
            }
        }
    }
    
    private var isValid: Bool {
        guard !symbol.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let sharesNum = Double(shares), sharesNum > 0 else { return false }
        guard let priceNum = Double(price), priceNum > 0 else { return false }
        
        if mode == .sell {
            guard let position = existingPosition, sharesNum <= position.shares else { return false }
        }
        
        return true
    }
    
    private func performAction() {
        guard let sharesNum = Double(shares),
              let priceNum = Double(price) else { return }
        
        let feesNum = Double(fees) ?? 0
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        
        do {
            switch mode {
            case .add:
                try viewModel.addPositionWithTransaction(
                    symbol: trimmedSymbol,
                    name: trimmedName.isEmpty ? trimmedSymbol : trimmedName,
                    assetType: assetType,
                    market: market,
                    shares: sharesNum,
                    costBasis: priceNum,
                    fees: feesNum
                )
                
            case .buyMore:
                guard let position = existingPosition else { return }
                try viewModel.buyMorePosition(
                    position,
                    shares: sharesNum,
                    price: priceNum,
                    fees: feesNum
                )
                
            case .sell:
                guard let position = existingPosition else { return }
                try viewModel.sellPosition(
                    position,
                    shares: sharesNum,
                    price: priceNum,
                    fees: feesNum
                )
                
            case .edit:
                guard let position = existingPosition else { return }
                try viewModel.updatePosition(
                    position,
                    symbol: trimmedSymbol,
                    name: trimmedName.isEmpty ? trimmedSymbol : trimmedName,
                    assetType: assetType,
                    market: market,
                    shares: sharesNum,
                    costBasis: priceNum
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview("Add") {
    PositionManagementSheet(mode: .add, viewModel: PortfolioDetailViewModel())
}

private func makePreviewPosition() -> Position {
    let context = PersistenceController.preview.container.viewContext
    let position = Position(context: context)
    position.symbol = "AAPL"
    position.name = "Apple Inc."
    position.shares = 100
    position.costBasis = 175.0
    return position
}
