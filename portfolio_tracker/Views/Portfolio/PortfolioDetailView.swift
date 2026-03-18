//
//  PortfolioDetailView.swift
//  portfolio_tracker
//
//  Main detail view for portfolio positions
//

import SwiftUI
import Charts

/// Detail view showing portfolio positions and analytics
struct PortfolioDetailView: View {
    @State private var viewModel: PortfolioDetailViewModel
    @State private var showingAddPositionSheet = false
    @State private var showingRebalancingView = false
    
    let portfolio: Portfolio?
    
    init(viewModel: PortfolioDetailViewModel, portfolio: Portfolio?) {
        _viewModel = State(initialValue: viewModel)
        self.portfolio = portfolio
    }
    
    var body: some View {
        Group {
            if let portfolioData = viewModel.portfolioViewData {
                contentView(portfolioData: portfolioData)
                    .onAppear {
                        if let portfolio = portfolio {
                            viewModel.setPortfolio(portfolio)
                        }
                    }
                    .onChange(of: portfolio?.id) { _, _ in
                        if let portfolio = portfolio {
                            viewModel.setPortfolio(portfolio)
                        }
                    }
            } else {
                emptyStateView
            }
        }
        .sheet(isPresented: $showingAddPositionSheet) {
            AddPositionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingRebalancingView) {
            RebalancingView(portfolio: portfolio)
        }
    }
    
    // MARK: - Subviews
    
    private func contentView(portfolioData: PortfolioViewData) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary cards
                summarySection(portfolioData: portfolioData)
                
                // Allocation chart
                if !viewModel.positionViewData.isEmpty {
                    allocationSection
                }
                
                // Positions list
                positionsSection
            }
            .padding()
        }
        .navigationTitle(portfolioData.name)
        .toolbar {
            ToolbarItemGroup {
                Button(action: { showingRebalancingView = true }) {
                    Label("再平衡", systemImage: "arrow.left.arrow.right")
                }
                .disabled(viewModel.positionViewData.isEmpty)
                .help(viewModel.positionViewData.isEmpty ? "需要先添加持仓" : "分析再平衡需求")
                
                Button(action: { showingAddPositionSheet = true }) {
                    Label("添加持仓", systemImage: "plus")
                }
                .help("添加新持仓")
            }
        }
    }
    
    private func summarySection(portfolioData: PortfolioViewData) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            SummaryCard(
                title: "总市值",
                value: portfolioData.totalValue.formattedAsCurrency(),
                icon: "dollarsign.circle.fill",
                color: .blue
            )
            
            SummaryCard(
                title: "总成本",
                value: portfolioData.totalCost.formattedAsCurrency(),
                icon: "bag.fill",
                color: .gray
            )
            
            SummaryCard(
                title: "盈亏",
                value: portfolioData.totalProfitLoss.formattedAsCurrency(),
                subtitle: portfolioData.profitLossPercentage.formattedAsPercentage(),
                icon: portfolioData.totalProfitLoss >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                color: portfolioData.totalProfitLoss >= 0 ? .green : .red
            )
        }
    }
    
    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("资产配置")
                .font(.headline)
            
            Chart(viewModel.positionViewData) { position in
                SectorMark(
                    angle: .value("Value", position.currentValue),
                    innerRadius: .ratio(0.618),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Symbol", position.symbol))
            }
            .frame(height: 200)
            .chartLegend(position: .trailing, alignment: .center)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("持仓明细 (\(viewModel.positionViewData.count))")
                    .font(.headline)
                
                Spacer()
                
                Button("更新价格") {
                    Task {
                        await viewModel.updateAllPrices()
                    }
                }
                .disabled(viewModel.isLoading || viewModel.positionViewData.isEmpty)
            }
            
            if viewModel.positionViewData.isEmpty {
                ContentUnavailableView {
                    Label("暂无持仓", systemImage: "doc.text")
                } description: {
                    Text("点击 + 按钮添加您的第一个持仓")
                }
                .frame(height: 200)
            } else {
                positionsTable
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var positionsTable: some View {
        Table(viewModel.positionViewData) {
            TableColumn("代码") { position in
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.symbol)
                        .fontWeight(.medium)
                    Text(position.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 120)
            
            TableColumn("类型") { position in
                Text(position.assetType.displayName)
                    .font(.caption)
            }
            .width(60)
            
            TableColumn("数量") { position in
                Text(String(format: "%.2f", position.shares))
                    .monospacedDigit()
            }
            .width(80)
            
            TableColumn("现价") { position in
                Text(position.currentPrice.formattedAsCurrency())
                    .monospacedDigit()
            }
            .width(100)
            
            TableColumn("市值") { position in
                Text(position.currentValue.formattedAsCurrency())
                    .monospacedDigit()
            }
            .width(100)
            
            TableColumn("权重") { position in
                Text(position.weightInPortfolio.formattedAsPercentage())
                    .monospacedDigit()
            }
            .width(70)
            
            TableColumn("盈亏") { position in
                PriceChangeLabel(
                    value: position.profitLoss,
                    percentage: position.profitLossPercentage
                )
            }
            .width(100)
        }
        .frame(minHeight: 200)
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("选择投资组合", systemImage: "briefcase")
        } description: {
            Text("从左侧列表选择一个投资组合查看详情")
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let title: String
    let value: String
    var subtitle: String?
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Add Position Sheet

/// Sheet for adding a new position with inline validation
struct AddPositionSheet: View {
    var viewModel: PortfolioDetailViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var symbol = ""
    @State private var name = ""
    @State private var assetType: AssetType = .stock
    @State private var market: Market = .us
    @State private var shares = ""
    @State private var costBasis = ""
    @State private var attemptedSubmit = false
    
    // MARK: - Validation
    
    private var symbolError: String? {
        if attemptedSubmit && symbol.trimmingCharacters(in: .whitespaces).isEmpty {
            return "请输入股票代码"
        }
        return nil
    }
    
    private var nameError: String? {
        if attemptedSubmit && name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "请输入资产名称"
        }
        return nil
    }
    
    private var sharesError: String? {
        if attemptedSubmit {
            if shares.isEmpty {
                return "请输入数量"
            }
            if Double(shares) == nil {
                return "请输入有效的数字"
            }
            if let value = Double(shares), value <= 0 {
                return "数量必须大于0"
            }
        }
        return nil
    }
    
    private var costBasisError: String? {
        if attemptedSubmit {
            if costBasis.isEmpty {
                return "请输入成本价"
            }
            if Double(costBasis) == nil {
                return "请输入有效的数字"
            }
            if let value = Double(costBasis), value <= 0 {
                return "成本价必须大于0"
            }
        }
        return nil
    }
    
    private var isValid: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(shares) != nil && Double(shares)!.isFinite && Double(shares)! > 0 &&
        Double(costBasis) != nil && Double(costBasis)!.isFinite && Double(costBasis)! > 0
    }
    
    private var validationMessage: String? {
        let errors = [symbolError, nameError, sharesError, costBasisError].compactMap { $0 }
        if attemptedSubmit && !errors.isEmpty {
            return errors.first
        }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("代码 (如 AAPL)", text: $symbol)
                            .textFieldStyle(.roundedBorder)
                        if let error = symbolError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("名称", text: $name)
                            .textFieldStyle(.roundedBorder)
                        if let error = nameError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    Picker("资产类型", selection: $assetType) {
                        ForEach(AssetType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    Picker("市场", selection: $market) {
                        ForEach(Market.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                }
                
                Section("持仓") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("数量", text: $shares)
                            .textFieldStyle(.roundedBorder)
                        if let error = sharesError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("成本价", text: $costBasis)
                            .textFieldStyle(.roundedBorder)
                        if let error = costBasisError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                // Validation summary
                if let message = validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("添加持仓")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        attemptedSubmit = true
                        if isValid {
                            addPosition()
                        }
                    }
                    .disabled(attemptedSubmit && !isValid)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
    
    private func addPosition() {
        guard let sharesNum = Double(shares),
              let costNum = Double(costBasis) else { return }
        
        viewModel.addPosition(
            symbol: symbol,
            name: name,
            assetType: assetType,
            market: market,
            shares: sharesNum,
            costBasis: costNum
        )
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let portfolio = Portfolio(context: context)
    portfolio.name = "示例组合"
    
    return NavigationStack {
        PortfolioDetailView(
            viewModel: PortfolioDetailViewModel(),
            portfolio: portfolio
        )
        .environment(\.managedObjectContext, context)
    }
}
