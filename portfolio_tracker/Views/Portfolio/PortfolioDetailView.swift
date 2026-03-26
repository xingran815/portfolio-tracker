//
//  PortfolioDetailView.swift
//  portfolio_tracker
//
//  Main detail view for portfolio positions
//

import SwiftUI
import Charts

struct PositionSheetItem: Identifiable {
    let id = UUID()
    let position: Position?
    let mode: PositionManagementMode
}

/// Detail view showing portfolio positions and analytics
struct PortfolioDetailView: View {
    @State private var viewModel = PortfolioDetailViewModel()
    @State private var showingRebalancingView = false
    @State private var showingSettingsWindow = false
    @State private var showingEditSheet = false
    @State private var positionSheetItem: PositionSheetItem?
    @State private var showingDeleteConfirmation = false
    @State private var positionToDelete: Position?
    @State private var exchangeRates: [String: Double] = [:]
    @State private var exchangeRateError: String?
    
    let portfolio: Portfolio?
    
    init(portfolio: Portfolio?) {
        self.portfolio = portfolio
    }
    
    var body: some View {
        Group {
            if let portfolio = portfolio {
                contentView(portfolio: portfolio)
                    .onAppear {
                        viewModel.setPortfolio(portfolio)
                        Task {
                            await fetchExchangeRates()
                        }
                    }
                    .onChange(of: portfolio.id) { _, _ in
                        viewModel.setPortfolio(portfolio)
                        Task {
                            await fetchExchangeRates()
                        }
                    }
            } else {
                emptyStateView
            }
        }
        .sheet(item: $positionSheetItem) { item in
            PositionManagementSheet(
                mode: item.mode,
                viewModel: viewModel,
                existingPosition: item.position
            )
        }
        .sheet(isPresented: $showingRebalancingView) {
            RebalancingView(portfolio: portfolio)
        }
        .sheet(isPresented: $showingEditSheet) {
            if let portfolio = portfolio {
                EditPortfolioView(portfolio: portfolio) { _ in
                    viewModel.setPortfolio(portfolio)
                    Task {
                        await fetchExchangeRates()
                    }
                }
            }
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let position = positionToDelete {
                    viewModel.deletePosition(position)
                }
            }
        } message: {
            if let position = positionToDelete {
                Text("确定要删除持仓 \(position.symbol ?? "") 吗？此操作无法撤销。")
            }
        }
    }
    
    // MARK: - Subviews
    
    private func contentView(portfolio: Portfolio) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary cards
                summarySection(portfolio: portfolio)
                
                // Allocation chart
                if !viewModel.positions.isEmpty {
                    allocationSection
                }
                
                // Positions list
                positionsSection
            }
            .padding()
        }
        .navigationTitle(portfolio.name ?? "投资组合")
        .toolbar {
            ToolbarItemGroup {
                Button(action: { showingEditSheet = true }) {
                    Label("编辑", systemImage: "pencil")
                }
                
                Button(action: { showingRebalancingView = true }) {
                    Label("再平衡", systemImage: "arrow.left.arrow.right")
                }
                .disabled(viewModel.positions.isEmpty)
                
                Button(action: {
                    positionSheetItem = PositionSheetItem(position: nil, mode: .add)
                }) {
                    Label("添加持仓", systemImage: "plus")
                }
                
                Button(action: { showingSettingsWindow = true }) {
                    Label("设置", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showingSettingsWindow) {
            SettingsWindow()
        }
    }
    
    private func summarySection(portfolio: Portfolio) -> some View {
        let convertedValue = exchangeRates.isEmpty ? viewModel.totalValue : portfolio.totalValueIn(currency: portfolio.currency, rates: exchangeRates)
        let convertedCost = exchangeRates.isEmpty ? viewModel.totalCost : portfolio.totalCostIn(currency: portfolio.currency, rates: exchangeRates)
        let convertedProfitLoss = convertedValue - convertedCost
        let profitLossPercent = convertedCost > 0 ? convertedProfitLoss / convertedCost : 0
        let pendingPriceCount = viewModel.positions.filter { $0.currentPrice == 0 }.count
        
        return VStack(spacing: 12) {
            SummaryCard(
                title: "总市值",
                value: formatCurrency(convertedValue, currency: portfolio.currency),
                icon: "dollarsign.circle.fill",
                color: .blue
            )
            
            SummaryCard(
                title: "总成本",
                value: formatCurrency(convertedCost, currency: portfolio.currency),
                icon: "bag.fill",
                color: .gray
            )
            
            SummaryCard(
                title: "盈亏",
                value: formatCurrency(convertedProfitLoss, currency: portfolio.currency),
                subtitle: profitLossPercent.formattedAsPercentage(),
                icon: convertedProfitLoss >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                color: convertedProfitLoss >= 0 ? .green : .red
            )
            
            if pendingPriceCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(pendingPriceCount) 个持仓价格待更新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            
            if exchangeRateError != nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("汇率获取失败，多币种资产显示可能不准确")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func formatCurrency(_ value: Double, currency: Currency) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.code
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(currency.symbol)\(String(format: "%.2f", value))"
    }
    
    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("资产配置")
                .font(.headline)
            
            Chart(viewModel.positions) { position in
                SectorMark(
                    angle: .value("Value", position.currentValue ?? 0),
                    innerRadius: .ratio(0.618),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Name", position.name ?? position.symbol ?? "Unknown"))
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
                Text("持仓明细 (\(viewModel.positionCount))")
                    .font(.headline)
                
                Spacer()
                
                Button("更新价格") {
                    Task {
                        await viewModel.updateAllPrices()
                    }
                }
                .disabled(viewModel.isLoading || viewModel.positions.isEmpty)
            }
            
            if viewModel.positions.isEmpty {
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
        Table(of: Position.self) {
            TableColumn("代码") { position in
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.symbol ?? "-")
                        .fontWeight(.medium)
                    Text(position.name ?? "")
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
            
            TableColumn("市值") { position in
                if position.currentPrice > 0 {
                    Text((position.currentValue ?? 0).formattedAsCurrency(currencyCode: position.currencyEnum.code))
                        .monospacedDigit()
                } else {
                    Text("待更新")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .width(100)
            
            TableColumn("盈亏") { position in
                if position.currentPrice > 0 {
                    let profitLoss = position.profitLoss ?? 0
                    Text(profitLoss.formattedAsCurrency(currencyCode: position.currencyEnum.code))
                        .monospacedDigit()
                        .foregroundStyle(profitLoss >= 0 ? .green : .red)
                } else {
                    Text("--")
                        .foregroundStyle(.secondary)
                }
            }
            .width(100)
            
            TableColumn("盈亏%") { position in
                if position.currentPrice > 0 {
                    Text((position.profitLossPercentage ?? 0).formattedAsPercentage())
                        .monospacedDigit()
                        .foregroundStyle((position.profitLoss ?? 0) >= 0 ? .green : .red)
                } else {
                    Text("--")
                        .foregroundStyle(.secondary)
                }
            }
            .width(70)
            
            TableColumn("数量") { position in
                Text(String(format: "%.2f", position.shares))
                    .monospacedDigit()
            }
            .width(80)
            
            TableColumn("现价") { position in
                if position.currentPrice > 0 {
                    Text(position.currentPrice.formattedAsCurrency(currencyCode: position.currencyEnum.code))
                        .monospacedDigit()
                } else {
                    Text("待更新")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .width(100)
            
            TableColumn("总投入") { position in
                Text(position.totalCost.formattedAsCurrency(currencyCode: position.currencyEnum.code))
                    .monospacedDigit()
            }
            .width(100)
        } rows: {
            ForEach(viewModel.positions) { position in
                TableRow(position)
                    .contextMenu {
                        Button {
                            positionSheetItem = PositionSheetItem(position: position, mode: .buyMore)
                        } label: {
                            Label("加仓", systemImage: "plus.circle")
                        }
                        
                        Button {
                            positionSheetItem = PositionSheetItem(position: position, mode: .sell)
                        } label: {
                            Label("卖出", systemImage: "minus.circle")
                        }
                        
                        Divider()
                        
                        Button {
                            positionSheetItem = PositionSheetItem(position: position, mode: .edit)
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        
                        Button {
                            Task {
                                await viewModel.updatePrice(for: position)
                            }
                        } label: {
                            Label("更新价格", systemImage: "arrow.clockwise")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            positionToDelete = position
                            showingDeleteConfirmation = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
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
    
    private func fetchExchangeRates() async {
        do {
            exchangeRates = try await ExchangeRateProvider.shared.fetchRates(base: "USD")
            exchangeRateError = nil
        } catch {
            exchangeRateError = error.localizedDescription
            print("Failed to fetch exchange rates: \(error)")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let portfolio = Portfolio(context: context)
    portfolio.name = "示例组合"
    
    return NavigationStack {
        PortfolioDetailView(portfolio: portfolio)
            .environment(\.managedObjectContext, context)
    }
}
