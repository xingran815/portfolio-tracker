//
//  PortfolioListView.swift
//  portfolio_tracker
//
//  Sidebar view for portfolio list
//

import SwiftUI

/// Sidebar view showing list of portfolios
struct PortfolioListView: View {
    @State private var viewModel: PortfolioListViewModel
    @State private var showingAddSheet = false
    @State private var newPortfolioName = ""
    @State private var selectedRiskProfile: RiskProfile = .moderate
    
    init(viewModel: PortfolioListViewModel? = nil) {
        // Initialize with provided viewModel or create new one
        _viewModel = State(initialValue: viewModel ?? PortfolioListViewModel())
    }
    
    var body: some View {
        List(selection: $viewModel.selectedPortfolioId) {
            Section("投资组合") {
                ForEach(viewModel.portfolios) { portfolio in
                    NavigationLink(value: portfolio.id) {
                        PortfolioRowView(portfolio: portfolio)
                    }
                    .tag(portfolio.id)
                }
                .onDelete { indexSet in
                    viewModel.deletePortfolios(at: indexSet)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("投资组合")
        .toolbar {
            ToolbarItem {
                Button(action: { showingAddSheet = true }) {
                    Label("新建组合", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            addPortfolioSheet
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "发生错误")
        }
        .overlay {
            if viewModel.portfolios.isEmpty {
                emptyStateView
            }
        }
    }
    
    // MARK: - Subviews
    
    private var addPortfolioSheet: some View {
        NavigationStack {
            Form {
                Section("组合信息") {
                    TextField("组合名称", text: $newPortfolioName)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("风险偏好", selection: $selectedRiskProfile) {
                        ForEach(RiskProfile.allCases, id: \.self) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                }
                
                Section {
                    Text("创建后将可以添加持仓和设置目标配置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("新建组合")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showingAddSheet = false
                        newPortfolioName = ""
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        viewModel.createPortfolio(
                            name: newPortfolioName,
                            riskProfile: selectedRiskProfile
                        )
                        showingAddSheet = false
                        newPortfolioName = ""
                    }
                    .disabled(newPortfolioName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 250)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "briefcase")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("暂无投资组合")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("创建您的第一个投资组合开始追踪")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button(action: { showingAddSheet = true }) {
                Label("新建组合", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Portfolio Row

/// Row view for a single portfolio in the list
struct PortfolioRowView: View {
    let portfolio: Portfolio
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(portfolio.name ?? "未命名")
                    .font(.headline)
                
                Spacer()
                
                RiskBadge(profile: portfolio.riskProfile)
            }
            
            HStack {
                Text(portfolio.totalValue.formattedAsCurrency())
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                PriceChangeLabel(
                    value: portfolio.totalProfitLoss,
                    percentage: portfolio.profitLossPercentage
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

// MARK: - Risk Badge

/// Small badge showing risk profile
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

// MARK: - Preview

#Preview {
    NavigationStack {
        PortfolioListView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
