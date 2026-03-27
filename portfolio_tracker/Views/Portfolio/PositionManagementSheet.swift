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
    @State private var assetType: AssetType = .fund
    @State private var market: Market = .cn
    @State private var currency: Currency = .cny
    @State private var entryMode: EntryMode = .quickImport
    @State private var amount = ""
    @State private var shares = ""
    @State private var price = ""
    @State private var fees = ""
    
    @State private var totalInvested = ""
    @State private var currentValue = ""
    @State private var fetchedNav: Double?
    @State private var fetchedNavDate: String?
    @State private var fetchedDataProvider: String?
    @State private var isFetchingNav = false
    @State private var isUpdatingPrice = false
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var calculatedShares: Double? {
        guard let amountNum = Double(amount), amountNum > 0,
              let priceNum = Double(price), priceNum > 0 else { return nil }
        return amountNum / priceNum
    }
    
    private var quickImportShares: Double? {
        guard let currentVal = Double(currentValue), currentVal > 0,
              let nav = fetchedNav, nav > 0 else { return nil }
        return currentVal / nav
    }
    
    private var quickImportAverageCost: Double? {
        guard let invested = Double(totalInvested), invested > 0,
              let shares = quickImportShares, shares > 0 else { return nil }
        return invested / shares
    }
    
    private var effectiveShares: Double? {
        if assetType == .cash {
            return Double(amount)
        }
        switch entryMode {
        case .quickImport:
            return quickImportShares
        case .amount:
            return calculatedShares
        case .shares:
            return Double(shares)
        }
    }
    
    private var effectivePrice: Double? {
        if assetType == .cash {
            return 1.0
        }
        switch entryMode {
        case .quickImport:
            return quickImportAverageCost
        default:
            return Double(price)
        }
    }
    
    init(mode: PositionManagementMode, viewModel: PortfolioDetailViewModel, existingPosition: Position? = nil) {
        self.mode = mode
        self.viewModel = viewModel
        self.existingPosition = existingPosition
        
        if let position = existingPosition {
            _symbol = State(initialValue: position.symbol ?? "")
            _name = State(initialValue: position.name ?? "")
            _assetType = State(initialValue: position.assetType)
            _market = State(initialValue: position.market)
            _currency = State(initialValue: position.currencyEnum)
            _entryMode = State(initialValue: position.entryMode)
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
                
                if isUpdatingPrice {
                    Section {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在更新价格...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isUpdatingPrice)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.confirmButton) {
                        performAction()
                    }
                    .disabled(!isValid || isUpdatingPrice)
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
            if entryMode != .quickImport {
                TextField("代码 (如 AAPL)", text: $symbol)
                    .textFieldStyle(.roundedBorder)
                    .disabled(mode != .add)
            }
            
            TextField("名称 (可选)", text: $name)
                .textFieldStyle(.roundedBorder)
                .disabled(mode == .buyMore || mode == .sell)
            
            Picker("资产类型", selection: $assetType) {
                ForEach(AssetType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .disabled(mode == .buyMore || mode == .sell)
            .onChange(of: assetType) { _, newValue in
                if newValue == .cash {
                    entryMode = .amount
                }
            }
            
            if assetType != .cash {
                Picker("市场", selection: $market) {
                    ForEach(Market.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .disabled(mode == .buyMore || mode == .sell)
            }
            
            Picker("币种", selection: $currency) {
                ForEach(Currency.allCases, id: \.self) { c in
                    Text(c.displayName).tag(c)
                }
            }
            .disabled(mode == .buyMore || mode == .sell)
        }
    }
    
    private var transactionSection: some View {
        Section(mode == .edit ? "持仓信息" : "交易信息") {
            // 现金类型：只显示金额输入
            if assetType == .cash {
                HStack {
                    TextField("金额", text: $amount)
                        .textFieldStyle(.roundedBorder)
                    Text(currency.symbol)
                        .foregroundStyle(.secondary)
                }
            } else {
                // 非现金：原有逻辑
                if (mode == .add || mode == .buyMore || mode == .edit) {
                    Picker("录入方式", selection: $entryMode) {
                        ForEach(EntryMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
                
                if entryMode == .quickImport && (mode == .add || mode == .buyMore || mode == .edit) {
                    HStack {
                        TextField("基金代码", text: $symbol)
                            .textFieldStyle(.roundedBorder)
                        
                        Button(action: fetchFundNav) {
                            if isFetchingNav {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("获取净值")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(symbol.isEmpty || isFetchingNav)
                    }
                    
                    if let nav = fetchedNav, let date = fetchedNavDate {
                        LabeledContent("当前净值", value: String(format: "%.4f", nav))
                            .foregroundStyle(.secondary)
                        LabeledContent("净值日期", value: date)
                            .foregroundStyle(.secondary)
                        if let provider = fetchedDataProvider {
                            LabeledContent("数据来源", value: provider)
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    } else if entryMode == .quickImport && symbol.count == 6 && symbol.allSatisfy({ $0.isNumber }) {
                        Text("请点击 \"获取净值\" 按钮获取基金净值")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    
                    HStack {
                        TextField("总投入金额", text: $totalInvested)
                            .textFieldStyle(.roundedBorder)
                        Text(currency.symbol)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        TextField("当前市值", text: $currentValue)
                            .textFieldStyle(.roundedBorder)
                        Text(currency.symbol)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let shares = quickImportShares {
                        LabeledContent("计算份额", value: String(format: "%.4f", shares))
                            .foregroundStyle(.blue)
                    }
                    
                    if let cost = quickImportAverageCost {
                        LabeledContent("平均成本", value: String(format: "%.4f", cost))
                            .foregroundStyle(.blue)
                    }
                    
                    if let invested = Double(totalInvested),
                       let current = Double(currentValue) {
                        let gainLoss = current - invested
                        let percentage = invested > 0 ? (gainLoss / invested) * 100 : 0
                        LabeledContent("预估盈亏", value: String(format: "%@%.2f (%+.2f%%)",
                            gainLoss >= 0 ? "+" : "",
                            gainLoss,
                            percentage))
                            .foregroundStyle(gainLoss >= 0 ? .green : .red)
                    }
                    
                } else if entryMode == .amount && (mode == .add || mode == .buyMore || mode == .edit) {
                    HStack {
                        TextField("投入金额", text: $amount)
                            .textFieldStyle(.roundedBorder)
                        
                        Text(currency.symbol)
                            .foregroundStyle(.secondary)
                    }
                    
                    TextField("买入价格", text: $price)
                        .textFieldStyle(.roundedBorder)
                    
                    if let calculated = calculatedShares {
                        LabeledContent("计算份额", value: String(format: "%.4f", calculated))
                            .foregroundStyle(.blue)
                    }
                } else {
                    HStack {
                        TextField(mode == .sell ? "卖出数量" : "数量", text: $shares)
                            .textFieldStyle(.roundedBorder)
                        
                        if mode == .sell, let position = existingPosition {
                            Text("/ \(String(format: "%.2f", position.shares))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("股")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    TextField(mode == .sell ? "卖出价格" : "成本价", text: $price)
                        .textFieldStyle(.roundedBorder)
                }
                
                TextField("手续费 (可选)", text: $fees)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
    
    private func fetchFundNav() {
        guard !symbol.isEmpty else { return }
        
        isFetchingNav = true
        let fundCode = symbol.trimmingCharacters(in: .whitespaces)
        
        Task {
            do {
                let provider = ChinaFundProvider()
                let quote = try await provider.fetchQuote(symbol: fundCode, market: .cn)
                
                await MainActor.run {
                    fetchedNav = quote.price
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    fetchedNavDate = dateFormatter.string(from: quote.lastUpdated)
                    fetchedDataProvider = quote.dataProvider
                    market = .cn
                    assetType = .fund
                    isFetchingNav = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "获取净值失败: \(error.localizedDescription)"
                    showError = true
                    isFetchingNav = false
                }
            }
        }
    }
    
    private var currentInfoSection: some View {
        Section {
            if let position = existingPosition {
                LabeledContent("当前持有", value: String(format: "%.2f 股", position.shares))
                LabeledContent("当前成本", value: String(format: "%.2f", position.costBasis))
                
                if mode == .buyMore, let sharesNum = effectiveShares, let priceNum = Double(price) {
                    let newTotalShares = position.shares + sharesNum
                    let newAvgCost = ((position.shares * position.costBasis) + (sharesNum * priceNum)) / newTotalShares
                    LabeledContent("加仓后平均成本", value: String(format: "%.2f", newAvgCost))
                        .foregroundStyle(.blue)
                }
                
                if mode == .sell {
                    if let sharesNum = effectiveShares, let priceNum = Double(price), sharesNum <= position.shares {
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
        // 现金类型：只需要金额 > 0
        if assetType == .cash {
            guard let amountNum = Double(amount), amountNum > 0 else { return false }
            return true
        }
        
        guard !symbol.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        
        // Quick import mode requires successful NAV fetch
        if entryMode == .quickImport && (mode == .add || mode == .buyMore) {
            guard fetchedNav != nil else { return false }
        }
        
        guard let sharesNum = effectiveShares, sharesNum > 0 else { return false }
        guard let priceNum = effectivePrice, priceNum > 0 else { return false }
        
        if mode == .sell {
            guard let position = existingPosition, sharesNum <= position.shares else { return false }
        }
        
        return true
    }
    
    private func performAction() {
        guard let sharesNum = effectiveShares,
              let priceNum = effectivePrice else { return }
        
        let feesNum = Double(fees) ?? 0
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        
        let initialPrice: Double
        if assetType == .cash {
            initialPrice = 1.0
        } else {
            initialPrice = fetchedNav ?? 0
        }
        
        let shouldUpdatePrice = assetType != .cash && (fetchedNav == nil || mode == .buyMore || mode == .sell || mode == .edit)
        
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
                    currency: currency,
                    entryMode: entryMode,
                    initialPrice: initialPrice,
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
                    costBasis: priceNum,
                    entryMode: entryMode
                )
            }
            
            if shouldUpdatePrice {
                isUpdatingPrice = true
                Task {
                    await viewModel.updatePriceForSymbol(trimmedSymbol)
                    await MainActor.run {
                        viewModel.refreshData()
                        isUpdatingPrice = false
                        dismiss()
                    }
                }
            } else {
                viewModel.refreshData()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview("Add") {
    PositionManagementSheet(mode: .add, viewModel: PortfolioDetailViewModel())
}

@MainActor
private func makePreviewPosition() -> Position {
    let context = PersistenceController.preview.container.viewContext
    let position = Position(context: context)
    position.symbol = "AAPL"
    position.name = "Apple Inc."
    position.shares = 100
    position.costBasis = 175.0
    return position
}
