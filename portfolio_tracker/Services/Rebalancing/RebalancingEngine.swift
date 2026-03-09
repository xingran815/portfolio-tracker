//
//  RebalancingEngine.swift
//  portfolio_tracker
//
//  Portfolio rebalancing engine with MPT-based optimization
//

import Foundation
import os.log

/// Configuration for rebalancing engine
struct RebalancingConfiguration: Sendable {
    /// Drift threshold to trigger rebalancing
    let driftThreshold: Double
    
    /// Whether to prioritize tax-loss harvesting
    let prioritizeTaxEfficiency: Bool
    
    /// Minimum order size (to avoid small trades)
    let minimumOrderSize: Double
    
    /// Maximum order size (to limit position sizes)
    let maximumOrderSize: Double?
    
    /// Cash buffer to maintain (percentage of portfolio)
    let cashBuffer: Double
    
    /// Strategy for order generation
    let strategy: RebalancingStrategy
    
    static let `default` = RebalancingConfiguration(
        driftThreshold: 0.05,
        prioritizeTaxEfficiency: true,
        minimumOrderSize: 100.0,
        maximumOrderSize: nil,
        cashBuffer: 0.02,
        strategy: .thresholdBased
    )
}

/// Rebalancing strategy type
enum RebalancingStrategy: String, Sendable {
    /// Simple threshold-based rebalancing
    case thresholdBased
    
    /// Cash-flow aware (minimize transactions)
    case cashFlowAware
    
    /// Tax-optimized (harvest losses first)
    case taxOptimized
}

/// Errors that can occur during rebalancing
enum RebalancingError: LocalizedError, Sendable {
    case noDriftAnalysis
    case insufficientCash(required: Double, available: Double)
    case invalidConfiguration(String)
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noDriftAnalysis:
            return "No drift analysis available"
        case .insufficientCash(let required, let available):
            return "Insufficient cash: need $\(String(format: "%.2f", required)), have $\(String(format: "%.2f", available))"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .generationFailed(let message):
            return "Failed to generate plan: \(message)"
        }
    }
}

/// Main rebalancing engine
actor RebalancingEngine {
    
    // MARK: - Properties
    
    private let configuration: RebalancingConfiguration
    private let driftAnalyzer: DriftAnalyzer
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "RebalancingEngine")
    
    // MARK: - Initialization
    
    /// Creates a rebalancing engine
    /// - Parameter configuration: Engine configuration
    init(configuration: RebalancingConfiguration = .default) {
        self.configuration = configuration
        self.driftAnalyzer = DriftAnalyzer(threshold: configuration.driftThreshold)
    }
    
    // MARK: - Public Methods
    
    /// Generates a rebalance plan for a portfolio
    /// - Parameters:
    ///   - portfolio: Portfolio to rebalance
    ///   - availableCash: Cash available for trading
    /// - Returns: Rebalance plan
    /// - Throws: RebalancingError if plan cannot be generated
    func generatePlan(
        for portfolio: Portfolio,
        availableCash: Double
    ) throws -> RebalancePlan {
        // Get positions
        let positionSet = portfolio.positions as? Set<Position> ?? []
        let positions = Array(positionSet)
        
        // Get target allocation
        let targetAllocation = portfolio.targetAllocation
        guard !targetAllocation.isEmpty else {
            throw RebalancingError.invalidConfiguration("No target allocation set")
        }
        
        // Get total value
        let totalValue = portfolio.totalValue
        guard totalValue > 0 else {
            throw RebalancingError.invalidConfiguration("Portfolio has no value")
        }
        
        // Analyze drift
        let driftAnalysis = try driftAnalyzer.analyze(
            positions: positions,
            targetAllocation: targetAllocation,
            totalValue: totalValue
        )
        
        logger.info("Generating rebalance plan for \(portfolio.name ?? "Portfolio")")
        logger.info("Total drift: \(driftAnalysis.totalDrift)")
        
        // Generate orders based on strategy
        let orders: [RebalanceOrder]
        switch configuration.strategy {
        case .thresholdBased:
            orders = try generateThresholdBasedOrders(
                analysis: driftAnalysis,
                positions: positions,
                totalValue: totalValue
            )
        case .cashFlowAware:
            orders = try generateCashFlowAwareOrders(
                analysis: driftAnalysis,
                positions: positions,
                availableCash: availableCash,
                totalValue: totalValue
            )
        case .taxOptimized:
            orders = try generateTaxOptimizedOrders(
                analysis: driftAnalysis,
                positions: positions,
                totalValue: totalValue
            )
        }
        
        // Validate orders
        guard !orders.isEmpty else {
            throw RebalancingError.generationFailed("No orders generated")
        }
        
        // Check cash requirements
        let plan = RebalancePlan(
            portfolioId: portfolio.id,
            portfolioName: portfolio.name,
            orders: orders,
            driftAnalysis: driftAnalysis
        )
        
        guard plan.canExecute(with: availableCash) else {
            throw RebalancingError.insufficientCash(
                required: plan.netCashNeeded,
                available: availableCash
            )
        }
        
        logger.info("Generated plan with \(orders.count) orders")
        return plan
    }
    
    /// Quick check if portfolio needs rebalancing
    /// - Parameter portfolio: Portfolio to check
    /// - Returns: True if rebalancing is recommended
    func needsRebalancing(_ portfolio: Portfolio) -> Bool {
        let positionSet = portfolio.positions as? Set<Position> ?? []
        let positions = Array(positionSet)
        let targetAllocation = portfolio.targetAllocation
        let totalValue = portfolio.totalValue
        
        guard !targetAllocation.isEmpty, totalValue > 0 else {
            return false
        }
        
        return driftAnalyzer.needsRebalancing(
            positions: positions,
            targetAllocation: targetAllocation,
            totalValue: totalValue
        )
    }
    
    /// Calculates next scheduled rebalancing date
    /// - Parameters:
    ///   - lastRebalanceDate: Date of last rebalance (nil if never)
    ///   - frequency: Rebalancing frequency
    /// - Returns: Next recommended date
    func nextRebalancingDate(
        lastRebalanceDate: Date?,
        frequency: RebalancingFrequency
    ) -> Date {
        let calendar = Calendar.current
        let baseDate = lastRebalanceDate ?? Date()
        
        switch frequency {
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: baseDate) ?? baseDate
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: baseDate) ?? baseDate
        }
    }
    
    /// Checks if rebalancing is overdue
    /// - Parameters:
    ///   - lastRebalanceDate: Date of last rebalance
    ///   - frequency: Rebalancing frequency
    /// - Returns: True if overdue
    func isRebalancingOverdue(
        lastRebalanceDate: Date?,
        frequency: RebalancingFrequency
    ) -> Bool {
        guard let lastDate = lastRebalanceDate else {
            return true  // Never rebalanced = overdue
        }
        
        let nextDate = nextRebalancingDate(
            lastRebalanceDate: lastDate,
            frequency: frequency
        )
        
        return Date() > nextDate
    }
}

// MARK: - Order Generation Strategies

private extension RebalancingEngine {
    
    /// Generates orders based on drift threshold
    func generateThresholdBasedOrders(
        analysis: DriftAnalysis,
        positions: [Position],
        totalValue: Double
    ) throws -> [RebalanceOrder] {
        var orders: [RebalanceOrder] = []
        
        // Process significant drifts
        for drift in analysis.significantDrifts {
            let order = try createOrder(
                for: drift,
                positions: positions,
                totalValue: totalValue
            )
            
            if let order = order {
                orders.append(order)
            }
        }
        
        return prioritizeOrders(orders)
    }
    
    /// Generates orders that work with available cash
    func generateCashFlowAwareOrders(
        analysis: DriftAnalysis,
        positions: [Position],
        availableCash: Double,
        totalValue: Double
    ) throws -> [RebalanceOrder] {
        var orders: [RebalanceOrder] = []
        var remainingCash = availableCash
        
        // First, generate sell orders (generates cash)
        for drift in analysis.significantDrifts where drift.isOverweight {
            if let order = try createOrder(
                for: drift,
                positions: positions,
                totalValue: totalValue
            ) {
                orders.append(order)
                remainingCash += order.estimatedAmount
            }
        }
        
        // Then, generate buy orders within cash limit
        for drift in analysis.significantDrifts where drift.isUnderweight {
            if let order = try createOrder(
                for: drift,
                positions: positions,
                totalValue: totalValue
            ) {
                if order.estimatedAmount <= remainingCash {
                    orders.append(order)
                    remainingCash -= order.estimatedAmount
                }
            }
        }
        
        return orders
    }
    
    /// Generates tax-optimized orders (harvest losses first)
    func generateTaxOptimizedOrders(
        analysis: DriftAnalysis,
        positions: [Position],
        totalValue: Double
    ) throws -> [RebalanceOrder] {
        var orders: [RebalanceOrder] = []
        
        // First priority: Sell positions with losses (tax loss harvesting)
        for drift in analysis.significantDrifts where drift.isOverweight {
            let position = positions.first { $0.symbol == drift.symbol }
            let hasLoss = (position?.profitLoss ?? 0) < 0
            
            if let order = try createOrder(
                for: drift,
                positions: positions,
                totalValue: totalValue
            ) {
                // Prioritize positions with losses
                let prioritizedOrder = hasLoss
                    ? order.withHighPriority()
                    : order
                orders.append(prioritizedOrder)
            }
        }
        
        // Second priority: Buy underweight positions
        for drift in analysis.significantDrifts where drift.isUnderweight {
            if let order = try createOrder(
                for: drift,
                positions: positions,
                totalValue: totalValue
            ) {
                orders.append(order)
            }
        }
        
        return orders.sorted { $0.priority > $1.priority }
    }
    
    /// Creates a single order from drift info
    func createOrder(
        for drift: PositionDrift,
        positions: [Position],
        totalValue: Double
    ) throws -> RebalanceOrder? {
        let symbol = drift.symbol
        
        // Determine action
        let action: OrderAction = drift.isOverweight ? .sell : .buy
        
        // Get current position
        let position = positions.first { $0.symbol == symbol }
        let currentPrice = position?.currentPrice ?? drift.currentValue / max(drift.currentWeight, 0.0001)
        
        guard currentPrice > 0 else {
            return nil
        }
        
        // Calculate shares to trade
        let adjustmentValue = abs(drift.adjustmentValue)
        let targetShares = adjustmentValue / currentPrice
        
        // Apply minimum order size
        guard adjustmentValue >= configuration.minimumOrderSize else {
            logger.debug("Order for \(symbol) below minimum size: $\(adjustmentValue)")
            return nil
        }
        
        // Apply maximum order size if configured
        var shares = targetShares
        if let maxSize = configuration.maximumOrderSize, adjustmentValue > maxSize {
            shares = maxSize / currentPrice
            logger.info("Order for \(symbol) capped at max size")
        }
        
        // Validate sell orders have sufficient shares
        if action == .sell {
            let availableShares = position?.shares ?? 0
            shares = min(shares, availableShares)
            
            guard shares > 0 else {
                logger.warning("Insufficient shares to sell \(symbol)")
                return nil
            }
        }
        
        // Generate reason
        let reason = generateReason(for: drift)
        
        return RebalanceOrder(
            symbol: symbol,
            action: action,
            shares: shares,
            estimatedPrice: currentPrice,
            priority: determinePriority(for: drift),
            reason: reason
        )
    }
    
    /// Generates human-readable reason for order
    func generateReason(for drift: PositionDrift) -> String {
        let driftPct = Int(drift.absoluteDrift * 100)
        let currentPct = Int(drift.currentWeight * 100)
        let targetPct = Int(drift.targetWeight * 100)
        
        if drift.isOverweight {
            return "Overweight by \(driftPct)% (current \(currentPct)%, target \(targetPct)%)"
        } else {
            return "Underweight by \(driftPct)% (current \(currentPct)%, target \(targetPct)%)"
        }
    }
    
    /// Determines order priority
    func determinePriority(for drift: PositionDrift) -> OrderPriority {
        let driftPct = drift.absoluteDrift
        
        if driftPct > 0.10 {
            return .high
        } else if driftPct > 0.05 {
            return .medium
        } else {
            return .low
        }
    }
    
    /// Prioritizes orders (sells first, then by drift magnitude)
    func prioritizeOrders(_ orders: [RebalanceOrder]) -> [RebalanceOrder] {
        orders.sorted { a, b in
            // Sell orders first
            if a.action == .sell && b.action == .buy {
                return true
            }
            if a.action == .buy && b.action == .sell {
                return false
            }
            // Then by priority
            return a.priority > b.priority
        }
    }
}

// MARK: - Convenience Extensions

extension RebalancingEngine {
    
    /// Generates a simple rebalance plan with default settings
    /// - Parameter portfolio: Portfolio to rebalance
    /// - Returns: Rebalance plan
    func generateSimplePlan(for portfolio: Portfolio) async throws -> RebalancePlan {
        try generatePlan(for: portfolio, availableCash: portfolio.totalValue)
    }
    
    /// Gets drift analysis for a portfolio
    /// - Parameter portfolio: Portfolio to analyze
    /// - Returns: Drift analysis
    func analyzeDrift(for portfolio: Portfolio) throws -> DriftAnalysis {
        let positionSet = portfolio.positions as? Set<Position> ?? []
        let positions = Array(positionSet)
        
        return try driftAnalyzer.analyze(
            positions: positions,
            targetAllocation: portfolio.targetAllocation,
            totalValue: portfolio.totalValue
        )
    }
}
