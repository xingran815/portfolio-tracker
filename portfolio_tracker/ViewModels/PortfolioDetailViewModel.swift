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
    
    /// Adds a new position with transaction record
    /// - Parameters:
    ///   - symbol: Stock/fund symbol
    ///   - name: Display name
    ///   - assetType: Type of asset
    ///   - market: Market identifier
    ///   - shares: Number of shares
    ///   - costBasis: Cost per share
    ///   - fees: Transaction fees
    func addPositionWithTransaction(
        symbol: String,
        name: String,
        assetType: AssetType,
        market: Market,
        shares: Double,
        costBasis: Double,
        fees: Double = 0
    ) throws {
        guard let portfolio = portfolio else { return }
        
        // Check for existing position
        if let existing = positions.first(where: { $0.symbol?.uppercased() == symbol.uppercased() }) {
            // Update existing position (average cost) - buy more
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
        
        // Record transaction
        _ = Transaction.create(
            in: viewContext,
            type: .buy,
            symbol: symbol,
            shares: shares,
            price: costBasis,
            fees: fees,
            portfolio: portfolio
        )
        
        portfolio.updatedAt = Date()
        try viewContext.save()
        loadPositions()
        logger.info("Added position with transaction: \(symbol)")
    }
    
    /// Buys more shares of an existing position
    /// - Parameters:
    ///   - position: Existing position
    ///   - shares: Number of shares to buy
    ///   - price: Price per share
    ///   - fees: Transaction fees
    func buyMorePosition(_ position: Position, shares: Double, price: Double, fees: Double = 0) throws {
        guard let portfolio = portfolio else { return }
        
        // Calculate new average cost
        let totalShares = position.shares + shares
        let totalCost = (position.shares * position.costBasis) + (shares * price)
        position.shares = totalShares
        position.costBasis = totalCost / totalShares
        
        // Record transaction
        _ = Transaction.create(
            in: viewContext,
            type: .buy,
            symbol: position.symbol ?? "",
            shares: shares,
            price: price,
            fees: fees,
            portfolio: portfolio
        )
        
        portfolio.updatedAt = Date()
        try viewContext.save()
        loadPositions()
        logger.info("Bought more \(position.symbol ?? ""): +\(shares) shares")
    }
    
    /// Sells shares of an existing position
    /// - Parameters:
    ///   - position: Existing position
    ///   - shares: Number of shares to sell
    ///   - price: Price per share
    ///   - fees: Transaction fees
    func sellPosition(_ position: Position, shares: Double, price: Double, fees: Double = 0) throws {
        guard let portfolio = portfolio else { return }
        guard position.shares >= shares else {
            throw PositionError.insufficientShares(available: position.shares, requested: shares)
        }
        
        // Record transaction before modifying position
        _ = Transaction.create(
            in: viewContext,
            type: .sell,
            symbol: position.symbol ?? "",
            shares: shares,
            price: price,
            fees: fees,
            portfolio: portfolio
        )
        
        // Reduce shares
        position.shares -= shares
        
        // Delete position if fully sold
        if position.shares == 0 {
            viewContext.delete(position)
        }
        
        portfolio.updatedAt = Date()
        try viewContext.save()
        loadPositions()
        logger.info("Sold \(position.symbol ?? ""): -\(shares) shares")
    }
    
    /// Updates position details manually (no transaction recorded)
    /// - Parameters:
    ///   - position: Position to update
    ///   - symbol: New symbol
    ///   - name: New name
    ///   - assetType: New asset type
    ///   - market: New market
    ///   - shares: New shares count
    ///   - costBasis: New cost basis
    func updatePosition(
        _ position: Position,
        symbol: String,
        name: String,
        assetType: AssetType,
        market: Market,
        shares: Double,
        costBasis: Double
    ) throws {
        position.symbol = symbol
        position.name = name
        position.assetTypeRaw = assetType.rawValue
        position.marketRaw = market.rawValue
        position.shares = shares
        position.costBasis = costBasis
        position.currency = market.currency
        
        if let portfolio = portfolio {
            portfolio.updatedAt = Date()
        }
        
        try viewContext.save()
        loadPositions()
        logger.info("Updated position: \(symbol)")
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
            
            position.updatePrice(quote.price, at: quote.lastUpdated)
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
