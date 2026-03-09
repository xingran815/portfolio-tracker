//
//  PortfolioDetailViewModel.swift
//  portfolio_tracker
//
//  ViewModel for portfolio detail view
//

import SwiftUI
import CoreData
import os.log

/// ViewModel for managing portfolio details and positions
@MainActor
@Observable
final class PortfolioDetailViewModel {
    
    // MARK: - Properties
    
    /// The portfolio being displayed
    var portfolio: Portfolio?
    
    /// Positions sorted by value
    var positions: [Position] = []
    
    /// Loading state
    var isLoading = false
    
    /// Error message
    var errorMessage: String?
    
    /// Show error alert
    var showError = false
    
    /// Rebalancing analysis result
    var driftAnalysis: DriftAnalysis?
    
    /// Rebalance plan
    var rebalancePlan: RebalancePlan?
    
    /// Whether rebalancing is being analyzed
    var isAnalyzing = false
    
    /// Available cash for trading (user input)
    var availableCash: Double = 0
    
    // MARK: - Dependencies
    
    private let viewContext: NSManagedObjectContext
    private let dataProvider: any DataProviderProtocol
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "PortfolioDetailViewModel")
    
    // MARK: - Initialization
    
    init(
        context: NSManagedObjectContext = PersistenceController.shared.viewContext,
        dataProvider: any DataProviderProtocol = MockDataProvider()
    ) {
        self.viewContext = context
        self.dataProvider = dataProvider
    }
    
    // MARK: - Public Methods
    
    /// Sets the current portfolio and loads its data
    /// - Parameter portfolio: Portfolio to display
    func setPortfolio(_ portfolio: Portfolio?) {
        self.portfolio = portfolio
        loadPositions()
        driftAnalysis = nil
        rebalancePlan = nil
    }
    
    /// Loads positions for current portfolio
    func loadPositions() {
        guard let portfolio = portfolio else {
            positions = []
            return
        }
        
        let positionSet = portfolio.positions as? Set<Position> ?? []
        positions = Array(positionSet).sorted { ($0.currentValue ?? 0) > ($1.currentValue ?? 0) }
    }
    
    /// Adds a new position to the portfolio
    /// - Parameters:
    ///   - symbol: Stock/fund symbol
    ///   - name: Display name
    ///   - assetType: Type of asset
    ///   - market: Market identifier
    ///   - shares: Number of shares
    ///   - costBasis: Cost per share
    func addPosition(
        symbol: String,
        name: String,
        assetType: AssetType,
        market: Market,
        shares: Double,
        costBasis: Double
    ) {
        guard let portfolio = portfolio else { return }
        
        // Check for existing position
        if let existing = positions.first(where: { $0.symbol?.uppercased() == symbol.uppercased() }) {
            // Update existing position (average cost)
            let totalShares = existing.shares + shares
            let totalCost = (existing.shares * existing.costBasis) + (shares * costBasis)
            existing.shares = totalShares
            existing.costBasis = totalCost / totalShares
        } else {
            // Create new position
            _ = Position.create(
                in: viewContext,
                symbol: symbol,
                name: name,
                assetType: assetType,
                market: market,
                shares: shares,
                costBasis: costBasis,
                portfolio: portfolio
            )
        }
        
        do {
            try viewContext.save()
            loadPositions()
            logger.info("Added position: \(symbol)")
        } catch {
            logger.error("Failed to save position: \(error.localizedDescription)")
            showError(message: "Failed to add position")
        }
    }
    
    /// Deletes a position
    /// - Parameter position: Position to delete
    func deletePosition(_ position: Position) {
        viewContext.delete(position)
        
        do {
            try viewContext.save()
            loadPositions()
            logger.info("Deleted position: \(position.symbol ?? "Unknown")")
        } catch {
            logger.error("Failed to delete position: \(error.localizedDescription)")
            showError(message: "Failed to delete position")
        }
    }
    
    /// Updates current price for a position
    /// - Parameter position: Position to update
    func updatePrice(for position: Position) async {
        guard let symbol = position.symbol else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let quote = try await dataProvider.fetchQuote(
                symbol: symbol,
                market: position.market
            )
            
            position.updatePrice(quote.price, at: quote.timestamp)
            try viewContext.save()
            loadPositions()
            
            logger.info("Updated price for \(symbol): \(quote.price)")
        } catch {
            logger.error("Failed to fetch price for \(symbol): \(error.localizedDescription)")
            showError(message: "Failed to fetch price for \(symbol)")
        }
    }
    
    /// Updates all position prices
    func updateAllPrices() async {
        for position in positions {
            await updatePrice(for: position)
            // Small delay to avoid rate limiting
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    
    /// Sets target allocation for the portfolio
    /// - Parameter allocation: Dictionary of symbol to target weight
    func setTargetAllocation(_ allocation: [String: Double]) {
        guard let portfolio = portfolio else { return }
        
        portfolio.targetAllocation = allocation
        portfolio.updatedAt = Date()
        
        do {
            try viewContext.save()
            logger.info("Updated target allocation")
        } catch {
            logger.error("Failed to save allocation: \(error.localizedDescription)")
            showError(message: "Failed to save target allocation")
        }
    }
    
    // MARK: - Computed Properties
    
    /// Total portfolio value
    var totalValue: Double {
        portfolio?.totalValue ?? 0
    }
    
    /// Total cost basis
    var totalCost: Double {
        portfolio?.totalCost ?? 0
    }
    
    /// Total profit/loss
    var totalProfitLoss: Double {
        portfolio?.totalProfitLoss ?? 0
    }
    
    /// Profit/loss percentage
    var profitLossPercentage: Double {
        portfolio?.profitLossPercentage ?? 0
    }
    
    /// Number of positions
    var positionCount: Int {
        positions.count
    }
    
    // MARK: - Private Helpers
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
