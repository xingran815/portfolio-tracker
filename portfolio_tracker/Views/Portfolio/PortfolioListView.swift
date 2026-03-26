//
//  PortfolioListView.swift
//  portfolio_tracker
//
//  Sidebar view for portfolio list
//

import SwiftUI
import UniformTypeIdentifiers
import CoreData
import Combine

struct PortfolioListView: View {
    @State private var viewModel: PortfolioListViewModel
    @State private var showingCreateSheet = false
    @State private var showingImportPicker = false
    @State private var importError: String?
    @State private var showingImportError = false
    @State private var portfolioToEdit: Portfolio?
    @State private var portfolioToDelete: Portfolio?
    @State private var showingDeleteConfirmation = false
    @State private var exchangeRates: [String: Double] = [:]
    @State private var cancellables = Set<AnyCancellable>()
    
    init(viewModel: PortfolioListViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? PortfolioListViewModel())
    }
    
    var body: some View {
        List(selection: $viewModel.selectedPortfolioId) {
            Section("投资组合") {
                ForEach(viewModel.portfolios) { portfolio in
                    NavigationLink(value: portfolio.id) {
                        PortfolioRowView(portfolio: portfolio, exchangeRates: exchangeRates)
                    }
                    .tag(portfolio.id)
                    .contextMenu {
                        Button {
                            portfolioToEdit = portfolio
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            portfolioToDelete = portfolio
                            showingDeleteConfirmation = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("投资组合")
        .onAppear {
            Task {
                await fetchExchangeRates()
            }
            setupCoreDataObserver()
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: { showingImportPicker = true }) {
                    Label("导入", systemImage: "arrow.down.doc")
                }
                .help("从 Markdown 文件导入")
                
                Button(action: { showingCreateSheet = true }) {
                    Label("新建组合", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePortfolioView { config in
                viewModel.createFromConfig(config)
            }
        }
        .sheet(item: $portfolioToEdit) { portfolio in
            EditPortfolioView(portfolio: portfolio) { _ in
                viewModel.refreshPortfolios()
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [UTType(filenameExtension: "md")!, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert("导入错误", isPresented: $showingImportError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importError ?? "未知错误")
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "发生错误")
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let portfolio = portfolioToDelete {
                    viewModel.deletePortfolio(portfolio)
                }
            }
        } message: {
            if let portfolio = portfolioToDelete {
                Text("确定要删除投资组合 \"\(portfolio.name ?? "")\" 吗？此操作无法撤销。")
            }
        }
        .overlay {
            if viewModel.portfolios.isEmpty {
                emptyStateView
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "briefcase")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("暂无投资组合")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("点击 + 按钮创建，或点击 ↓ 导入 Markdown 文件")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFromFile(url)
        case .failure(let error):
            importError = error.localizedDescription
            showingImportError = true
        }
    }
    
    private func importFromFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importError = "无法访问文件"
            showingImportError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let parser = MDParser()
            let config = try parser.parse(content)
            viewModel.createFromConfig(config)
        } catch let error as MDParserError {
            importError = "解析错误: \(error.localizedDescription)"
            showingImportError = true
        } catch {
            importError = "读取文件失败: \(error.localizedDescription)"
            showingImportError = true
        }
    }
    
    private func fetchExchangeRates() async {
        do {
            exchangeRates = try await ExchangeRateProvider.shared.fetchRates(base: "USD")
        } catch {
            print("Failed to fetch exchange rates: \(error)")
        }
    }
    
    private func setupCoreDataObserver() {
        NotificationCenter.default.publisher(
            for: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
            object: viewModel.viewContext
        )
        .receive(on: DispatchQueue.main)
        .sink { _ in
            viewModel.refreshPortfolios()
            Task {
                await fetchExchangeRates()
            }
        }
        .store(in: &cancellables)
    }
}

struct PortfolioRowView: View {
    let portfolio: Portfolio
    let exchangeRates: [String: Double]
    
    var convertedValue: Double {
        exchangeRates.isEmpty ? portfolio.totalValue : portfolio.totalValueIn(currency: portfolio.currency, rates: exchangeRates)
    }
    
    var convertedProfitLoss: Double {
        exchangeRates.isEmpty ? portfolio.totalProfitLoss : portfolio.totalProfitLossIn(currency: portfolio.currency, rates: exchangeRates)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(portfolio.name ?? "未命名")
                    .font(.headline)
                
                Spacer()
                
                RiskBadge(profile: portfolio.riskProfile)
            }
            
            HStack {
                Text(convertedValue.formattedAsCurrency(currencyCode: portfolio.currency.code))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                PriceChangeLabel(
                    value: convertedProfitLoss,
                    percentage: portfolio.profitLossPercentage,
                    currencyCode: portfolio.currency.code
                )
            }
            
            HStack {
                let positionCount = (portfolio.positions as? Set<Position>)?.count ?? 0
                Label("\(positionCount) 持仓", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(portfolio.rebalancingFrequency.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RiskBadge: View {
    let profile: RiskProfile
    
    var color: Color {
        switch profile {
        case .conservative: return .green
        case .moderate: return .blue
        case .aggressive: return .orange
        }
    }
    
    var body: some View {
        Text(profile.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        PortfolioListView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
