//
//  RebalancingView.swift
//  portfolio_tracker
//
//  Portfolio rebalancing analysis with visual and text modes
//

import SwiftUI
import Charts

/// View for portfolio rebalancing analysis
struct RebalancingView: View {
    @Environment(\.dismiss) private var dismiss
    let portfolio: Portfolio?
    
    @State private var viewMode: ViewMode = .visual
    @State private var selectedStrategy: RebalancingStrategyType = .threshold
    @State private var availableCash: String = "0"
    @State private var isAnalyzing = false
    @State private var driftAnalysis: DriftAnalysis?
    @State private var rebalancePlan: RebalancePlan?
    @State private var errorMessage: String?
    @State private var showingExecuteConfirmation = false
    @State private var showingTargetAllocationEditor = false
    
    enum ViewMode: String, CaseIterable {
        case visual = "图表"
        case text = "文本"
    }
    
    enum RebalancingStrategyType: String, CaseIterable {
        case threshold = "阈值策略"
        case cashFlow = "现金流策略"
        case taxOptimized = "税务优化"
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let portfolio = portfolio {
                    contentView(portfolio: portfolio)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("再平衡分析")

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .sheet(isPresented: $showingTargetAllocationEditor) {
            TargetAllocationEditorView(portfolio: portfolio)
        }
        .alert("执行再平衡计划", isPresented: $showingExecuteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认执行", role: .destructive) {
                executePlan()
            }
        } message: {
            Text("确定要执行此再平衡计划吗？这将生成相应的交易记录。")
        }
    }
    
    // MARK: - Subviews
    
    private func contentView(portfolio: Portfolio) -> some View {
        VStack(spacing: 0) {
            // Configuration bar
            configBar(portfolio: portfolio)
            
            Divider()
            
            // Results area
            if let error = errorMessage {
                errorView(error)
            } else if let plan = rebalancePlan {
                resultsView(plan: plan)
            } else if isAnalyzing {
                loadingView
            } else {
                readyView
            }
        }
    }
    
    private func configBar(portfolio: Portfolio) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // View mode picker
                Picker("显示模式", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode == .visual ? "chart.pie" : "text.alignleft")
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                
                Divider()
                    .frame(height: 24)
                
                // Strategy picker
                Picker("策略", selection: $selectedStrategy) {
                    ForEach(RebalancingStrategyType.allCases, id: \.self) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .frame(width: 150)
                
                Divider()
                    .frame(height: 24)
                
                // Available cash
                HStack(spacing: 8) {
                    Text("可用资金:")
                        .font(.subheadline)
                    TextField("0", text: $availableCash)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                Spacer()
                
                // Action buttons
                Button("设置目标") {
                    showingTargetAllocationEditor = true
                }
                
                Button("分析") {
                    analyzePortfolio(portfolio: portfolio)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzing)
            }
            
            // Portfolio summary
            HStack(spacing: 24) {
                Label("总市值: \(portfolio.totalValue.formattedAsCurrency())", systemImage: "dollarsign.circle")
                let positionCount = (portfolio.positions as? Set<Position>)?.count ?? 0
                Label("持仓数: \(positionCount)", systemImage: "number")
                Label("上次更新: \(portfolio.updatedAt?.formattedAsDate() ?? "-")", systemImage: "clock")
                
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func resultsView(plan: RebalancePlan) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Drift summary
                if let analysis = plan.driftAnalysis {
                    driftSummaryCard(analysis: analysis)
                }
                
                // Content based on view mode
                if viewMode == .visual {
                    visualResults(plan: plan)
                } else {
                    textResults(plan: plan)
                }
                
                // Execute button
                if !plan.orders.isEmpty {
                    executeButton(plan: plan)
                }
            }
            .padding()
        }
    }
    
    private func driftSummaryCard(analysis: DriftAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("漂移分析")
                        .font(.headline)
                    Text("阈值: \(Int(analysis.threshold * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Drift indicator
                HStack(spacing: 8) {
                    driftIndicator(value: analysis.totalDrift)
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(analysis.totalDrift * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("总漂移")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if analysis.needsRebalancing {
                Label("建议再平衡", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            } else {
                Label("配置合理", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func driftIndicator(value: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                .frame(width: 60, height: 60)
            
            Circle()
                .trim(from: 0, to: min(value, 1.0))
                .stroke(driftColor(value: value), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 60, height: 60)
                .rotationEffect(.degrees(-90))
            
            Text("\(Int(value * 100))%")
                .font(.caption)
                .fontWeight(.bold)
        }
    }
    
    private func driftColor(value: Double) -> Color {
        switch value {
        case 0..<0.05: return .green
        case 0.05..<0.10: return .yellow
        default: return .red
        }
    }
    
    private func visualResults(plan: RebalancePlan) -> some View {
        VStack(spacing: 20) {
            // Current vs Target allocation chart
            allocationComparisonChart
            
            // Drift bars
            driftBarsChart
            
            // Orders list
            if !plan.orders.isEmpty {
                ordersCard(plan: plan)
            }
        }
    }
    
    private var allocationComparisonChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("配置对比")
                .font(.headline)
            
            if let portfolio = portfolio {
                Chart {
                    // Current allocation
                    ForEach(Array(portfolio.positions as? Set<Position> ?? []), id: \.id) { position in
                        if let symbol = position.symbol {
                            BarMark(
                                x: .value("Symbol", symbol),
                                y: .value("Weight", position.weightInPortfolio ?? 0)
                            )
                            .foregroundStyle(.blue.opacity(0.7))
                            .position(by: .value("Type", "当前"))
                        }
                    }
                    
                    // Target allocation
                    ForEach(portfolio.targetAllocation.sorted(by: { $0.key < $1.key }), id: \.key) { symbol, weight in
                        BarMark(
                            x: .value("Symbol", symbol),
                            y: .value("Weight", weight)
                        )
                        .foregroundStyle(.green.opacity(0.7))
                        .position(by: .value("Type", "目标"))
                    }
                }
                .frame(height: 250)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(doubleValue.formattedAsPercentage())
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var driftBarsChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("漂移详情")
                .font(.headline)
            
            if let analysis = driftAnalysis {
                Chart(analysis.positions, id: \.symbol) { drift in
                    BarMark(
                        x: .value("Drift", drift.drift)
                    )
                    .foregroundStyle(drift.drift > 0 ? .green : .red)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let symbol = value.as(String.self) {
                                Text(symbol)
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(analysis.positions.count) * 40, 300))
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func ordersCard(plan: RebalancePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("建议操作 (\(plan.orders.count))")
                .font(.headline)
            
            ForEach(plan.prioritizedOrders) { order in
                OrderRow(order: order)
            }
            
            // Summary
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("买入总计: \(plan.totalBuyAmount.formattedAsCurrency())")
                        .foregroundStyle(.green)
                    Text("卖出总计: \(plan.totalSellAmount.formattedAsCurrency())")
                        .foregroundStyle(.red)
                    Text("净现金流: \(plan.netCashNeeded.formattedAsCurrency())")
                        .fontWeight(.bold)
                }
                .font(.caption)
                .monospacedDigit()
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func textResults(plan: RebalancePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("再平衡计划")
                .font(.headline)
            
            TextEditor(text: .constant(plan.summary))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 300)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func executeButton(plan: RebalancePlan) -> some View {
        Button {
            showingExecuteConfirmation = true
        } label: {
            Label("执行计划", systemImage: "play.circle.fill")
                .font(.headline)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(plan.canExecute(with: Double(availableCash) ?? 0))
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("正在分析投资组合...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var readyView: some View {
        ContentUnavailableView {
            Label("准备分析", systemImage: "arrow.left.arrow.right.circle")
        } description: {
            Text("选择策略并点击分析按钮开始")
        }
    }
    
    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("分析失败", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        } description: {
            Text(error)
        } actions: {
            Button("重试") {
                if let portfolio = portfolio {
                    analyzePortfolio(portfolio: portfolio)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("未选择组合", systemImage: "briefcase")
        } description: {
            Text("请先选择一个投资组合")
        }
    }
    
    // MARK: - Actions
    
    private func analyzePortfolio(portfolio: Portfolio) {
        isAnalyzing = true
        errorMessage = nil
        rebalancePlan = nil
        
        Task {
            do {
                // Create snapshot
                let snapshot = PortfolioSnapshot.from(portfolio)
                
                // Create engine with selected strategy
                let config = RebalancingConfiguration(
                    driftThreshold: 0.05,
                    prioritizeTaxEfficiency: selectedStrategy == .taxOptimized,
                    minimumOrderSize: 100,
                    maximumOrderSize: nil,
                    cashBuffer: 0.02,
                    maxPriceAge: 300,
                    strategy: getStrategy()
                )
                
                let engine = RebalancingEngine(configuration: config)
                
                // Generate plan
                let plan = try await engine.generatePlan(
                    from: snapshot,
                    availableCash: Double(availableCash) ?? 0
                )
                
                await MainActor.run {
                    self.rebalancePlan = plan
                    self.driftAnalysis = plan.driftAnalysis
                    self.isAnalyzing = false
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    private func getStrategy() -> any RebalancingStrategy {
        switch selectedStrategy {
        case .threshold:
            return ThresholdBasedStrategy()
        case .cashFlow:
            return CashFlowAwareStrategy()
        case .taxOptimized:
            return TaxOptimizedStrategy()
        }
    }
    
    private func executePlan() {
        // TODO: Implement plan execution
        // This would create transaction records and update positions
        errorMessage = "执行功能即将推出"
    }
}

// MARK: - Order Row

struct OrderRow: View {
    let order: RebalanceOrder
    
    var body: some View {
        HStack {
            // Action indicator
            Image(systemName: order.action == .buy ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(order.action == .buy ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(order.action.displayName) \(order.symbol)")
                    .fontWeight(.medium)
                Text(order.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(order.shares)) 股 @ \(order.estimatedPrice.formattedAsCurrency())")
                    .font(.subheadline)
                    .monospacedDigit()
                Text(order.estimatedAmount.formattedAsCurrency())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Target Allocation Editor

struct TargetAllocationEditorView: View {
    let portfolio: Portfolio?
    @Environment(\.dismiss) private var dismiss
    
    @State private var allocations: [String: Double] = [:]
    @State private var newSymbol = ""
    @State private var newWeight = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("当前目标配置") {
                    ForEach(allocations.sorted(by: { $0.key < $1.key }), id: \.key) { symbol, weight in
                        HStack {
                            Text(symbol)
                            Spacer()
                            Text(weight.formattedAsPercentage())
                                .monospacedDigit()
                            
                            Button {
                                allocations.removeValue(forKey: symbol)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    HStack {
                        TextField("代码", text: $newSymbol)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        
                        TextField("权重 (如 0.3)", text: $newWeight)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("添加") {
                            if let weight = Double(newWeight), !newSymbol.isEmpty {
                                allocations[newSymbol.uppercased()] = weight
                                newSymbol = ""
                                newWeight = ""
                            }
                        }
                        .disabled(newSymbol.isEmpty || Double(newWeight) == nil)
                    }
                }
                
                Section("总和") {
                    let total = allocations.values.reduce(0, +)
                    HStack {
                        Text("总权重")
                        Spacer()
                        Text(total.formattedAsPercentage())
                            .monospacedDigit()
                            .foregroundStyle(abs(total - 1.0) < 0.01 ? .green : .orange)
                    }
                    
                    if abs(total - 1.0) >= 0.01 {
                        Text("提示: 总权重应接近 100%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("目标配置")

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveAllocations()
                    }
                }
            }
            .onAppear {
                if let portfolio = portfolio {
                    allocations = portfolio.targetAllocation
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
    
    private func saveAllocations() {
        guard let portfolio = portfolio else {
            dismiss()
            return
        }
        
        portfolio.targetAllocation = allocations
        portfolio.updatedAt = Date()
        
        do {
            try PersistenceController.shared.save()
            dismiss()
        } catch {
            // Handle error
        }
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let portfolio = Portfolio(context: context)
    portfolio.name = "示例组合"
    
    return RebalancingView(portfolio: portfolio)
}
