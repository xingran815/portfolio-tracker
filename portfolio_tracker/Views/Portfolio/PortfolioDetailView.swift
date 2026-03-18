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
    @State private var viewModel = PortfolioDetailViewModel()
    @State private var showingAddPositionSheet = false
    @State private var showingRebalancingView = false
    @State private var showingSettingsWindow = false
    
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
                    }
                    .onChange(of: portfolio.id) { _, _ in
                        viewModel.setPortfolio(portfolio)
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
                Button(action: { showingRebalancingView = true }) {
                    Label("再平衡", systemImage: "arrow.left.arrow.right")
                }
                .disabled(viewModel.positions.isEmpty)
                
                Button(action: { showingAddPositionSheet = true }) {
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
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            SummaryCard(
                title: "总市值",
                value: viewModel.totalValue.formattedAsCurrency(),
                icon: "dollarsign.circle.fill",
                color: .blue
            )
            
            SummaryCard(
                title: "总成本",
                value: viewModel.totalCost.formattedAsCurrency(),
                icon: "bag.fill",
                color: .gray
            )
            
            SummaryCard(
                title: "盈亏",
                value: viewModel.totalProfitLoss.formattedAsCurrency(),
                subtitle: viewModel.profitLossPercentage.formattedAsPercentage(),
                icon: viewModel.totalProfitLoss >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                color: viewModel.totalProfitLoss >= 0 ? .green : .red
            )
        }
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
                .foregroundStyle(by: .value("Symbol", position.symbol ?? "Unknown"))
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
                Text((position.currentValue ?? 0).formattedAsCurrency())
                    .monospacedDigit()
            }
            .width(100)
            
            TableColumn("权重") { position in
                Text((position.weightInPortfolio ?? 0).formattedAsPercentage())
                    .monospacedDigit()
            }
            .width(70)
            
            TableColumn("盈亏") { position in
                PriceChangeLabel(
                    value: position.profitLoss ?? 0,
                    percentage: position.profitLossPercentage ?? 0
                )
            }
            .width(100)
        } rows: {
            ForEach(viewModel.positions) { position in
                TableRow(position)
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

struct AddPositionSheet: View {
    var viewModel: PortfolioDetailViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var symbol = ""
    @State private var name = ""
    @State private var assetType: AssetType = .stock
    @State private var market: Market = .us
    @State private var shares = ""
    @State private var costBasis = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("代码 (如 AAPL)", text: $symbol)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("名称", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
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
                    TextField("数量", text: $shares)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("成本价", text: $costBasis)
                        .textFieldStyle(.roundedBorder)
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
                        addPosition()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }
    
    private var isValid: Bool {
        !symbol.isEmpty &&
        !name.isEmpty &&
        Double(shares) != nil &&
        Double(costBasis) != nil
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
        PortfolioDetailView(portfolio: portfolio)
            .environment(\.managedObjectContext, context)
    }
}
