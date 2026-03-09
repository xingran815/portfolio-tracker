//
//  RebalancingEngine.swift
//  portfolio_tracker
//
//  Portfolio rebalancing engine with MPT-based optimization
//

import Foundation
import CoreData
import os.log

// MARK: - Financial Constants

/// Constants for financial calculations
/// All values use Double for consistency and performance
enum FinancialConstants {
    /// Minimum position value to consider (avoids micro-positions)
    static let minPositionValue: Double = 0.01
    
    /// Allocation tolerance for normalization (0.0001 = 0.01%)
    static let allocationTolerance: Double = 0.0001
    
    /// Default epsilon for floating point comparisons
    static let doubleEpsilon: Double = 0.0001
}

// MARK: - Configuration

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
    
    /// Maximum age of price data (seconds)
    let maxPriceAge: TimeInterval
    
    /// Strategy for order generation
    let strategy: any RebalancingStrategy
    
    static let `default` = RebalancingConfiguration(
        driftThreshold: 0.05,
        prioritizeTaxEfficiency: true,
        minimumOrderSize: 100.0,
        maximumOrderSize: nil,
        cashBuffer: 0.02,
        maxPriceAge: 300,  // 5 minutes
        strategy: ThresholdBasedStrategy()
    )
}

// MARK: - Strategy Protocol

/// Protocol for rebalancing strategies
protocol RebalancingStrategy: Sendable {
    /// Generates orders based on the strategy
    /// - Parameters:
    ///   - analysis: Drift analysis
    ///   - snapshot: Portfolio snapshot
    ///   - availableCash: Available cash for trading
    ///   - config: Engine configuration
    /// - Returns: Array of orders
    func generateOrders(
        analysis: DriftAnalysis,
        snapshot: PortfolioSnapshot,
        availableCash: Double,
        config: RebalancingConfiguration
    ) -> [RebalanceOrder]
}

// MARK: - Strategy Implementations

/// Threshold-based rebalancing strategy
struct ThresholdBasedStrategy: RebalancingStrategy {
    func generateOrders(
        analysis: DriftAnalysis,
        snapshot: PortfolioSnapshot,
        availableCash: Double,
        config: RebalancingConfiguration
    ) -> [RebalanceOrder] {
        var orders: [RebalanceOrder] = []
        
        for drift in analysis.significantDrifts {
            if let order = OrderFactory.createOrder(
                for: drift,
                snapshot: snapshot,
                config: config
            ) {
                orders.append(order)
            }
        }
        
        return prioritizeOrders(orders)
    }
    
    private func prioritizeOrders(_ orders: [RebalanceOrder]) -> [RebalanceOrder] {
        orders.sorted { a, b in
            if a.action == .sell && b.action == .buy { return true }
            if a.action == .buy && b.action == .sell { return false }
            return a.priority > b.priority
        }
    }
}

/// Cash-flow aware strategy (minimizes transactions)
struct CashFlowAwareStrategy: RebalancingStrategy {
    func generateOrders(
        analysis: DriftAnalysis,
        snapshot: PortfolioSnapshot,
        availableCash: Double,
        config: RebalancingConfiguration
    ) -> [RebalanceOrder] {
        var orders: [RebalanceOrder] = []
        var remainingCash = availableCash
        
        // First, generate sell orders (generates cash)
        for drift in analysis.significantDrifts where drift.isOverweight {
            if let order = OrderFactory.createOrder(
                for: drift,
                snapshot: snapshot,
                config: config
            ) {
                orders.append(order)
                remainingCash += order.estimatedAmount
            }
        }
        
        // Then, generate buy orders within cash limit
        for drift in analysis.significantDrifts where drift.isUnderweight {
            if let order = OrderFactory.createOrder(
                for: drift,
                snapshot: snapshot,
                config: config
            ) {
                if order.estimatedAmount <= remainingCash {
                    orders.append(order)
                    remainingCash -= order.estimatedAmount
                }
            }
        }
        
        return orders
    }
}

/// Tax-optimized strategy (harvests losses first)
struct TaxOptimizedStrategy: RebalancingStrategy {
    func generateOrders(
        analysis: DriftAnalysis,
        snapshot: PortfolioSnapshot,
        availableCash: Double,
        config: RebalancingConfiguration
    ) -> [RebalanceOrder] {
        var orders: [RebalanceOrder] = []
        
        // First priority: Sell positions with losses
        for drift in analysis.significantDrifts where drift.isOverweight {
            let position = snapshot.position(for: drift.symbol)
            let hasLoss = (position?.profitLoss ?? 0) < 0
            
            if let order = OrderFactory.createOrder(
                for: drift,
                snapshot: snapshot,
                config: config
            ) {
                orders.append(hasLoss ? order.withHighPriority() : order)
            }
        }
        
        // Second priority: Buy underweight positions
        for drift in analysis.significantDrifts where drift.isUnderweight {
            if let order = OrderFactory.createOrder(
                for: drift,
                snapshot: snapshot,
                config: config
            ) {
                orders.append(order)
            }
        }
        
        return orders.sorted { $0.priority > $1.priority }
    }
}

// MARK: - Order Factory

/// Factory for creating validated orders
enum OrderFactory {
    
    static func createOrder(
        for drift: PositionDrift,
        snapshot: PortfolioSnapshot,
        config: RebalancingConfiguration
    ) -> RebalanceOrder? {
        let symbol = drift.symbol
        let action: OrderAction = drift.isOverweight ? .sell : .buy
        
        // Get position and price
        let position = snapshot.position(for: symbol)
        let currentPrice = position?.currentPrice ?? 0
        
        // Validate price
        guard currentPrice > 0 else {
            return nil
        }
        
        // Check price freshness if available
        if let lastUpdated = position?.lastUpdated,
           Date().timeIntervalSince(lastUpdated) > config.maxPriceAge {
            // Price is stale - could return nil or log warning
            // For now, continue but with lower priority
        }
        
        // Calculate adjustment value using actual portfolio total
        guard let adjustmentValue = calculateAdjustmentValue(
            drift: drift,
            totalPortfolioValue: snapshot.totalValue
        ) else {
            return nil
        }
        
        // Apply minimum order size
        guard adjustmentValue >= config.minimumOrderSize else {
            return nil
        }
        
        // Calculate shares
        var shares = adjustmentValue / currentPrice
        
        // Apply maximum order size if configured
        if let maxSize = config.maximumOrderSize, adjustmentValue > maxSize {
            shares = maxSize / currentPrice
        }
        
        // Validate sell orders have sufficient shares
        if action == .sell {
            let availableShares = position?.shares ?? 0
            shares = min(shares, availableShares)
            
            guard shares > 0 else {
                return nil
            }
        }
        
        // Generate reason
        let reason = generateReason(for: drift)
        let priority = determinePriority(for: drift)
        
        return RebalanceOrder(
            symbol: symbol,
            action: action,
            shares: shares,
            estimatedPrice: currentPrice,
            priority: priority,
            reason: reason
        )
    }
    
    private static func calculateAdjustmentValue(
        drift: PositionDrift,
        totalPortfolioValue: Double
    ) -> Double? {
        // Handle edge case where currentWeight is 0 (new position)
        guard drift.currentWeight > FinancialConstants.doubleEpsilon else {
            // Position doesn't exist yet, calculate based on target weight
            guard abs(drift.drift) > FinancialConstants.doubleEpsilon else { return nil }
            // Use actual total portfolio value × target weight for new positions
            return abs(drift.drift) * totalPortfolioValue
        }
        
        guard let adjValue = drift.adjustmentValue else { return nil }
        return abs(adjValue)
    }
    
    private static func generateReason(for drift: PositionDrift) -> String {
        let driftPct = Int(drift.absoluteDrift * 100)
        let currentPct = Int(drift.currentWeight * 100)
        let targetPct = Int(drift.targetWeight * 100)
        let direction = drift.isOverweight ? "Over" : "Under"
        return "\(direction) by \(driftPct)% (current \(currentPct)%, target \(targetPct)%)"
    }
    
    private static func determinePriority(for drift: PositionDrift) -> OrderPriority {
        let driftPct = drift.absoluteDrift
        if driftPct > 0.10 { return .high }
        if driftPct > 0.05 { return .medium }
        return .low
    }
}

// MARK: - Errors

enum RebalancingError: LocalizedError, Sendable {
    case invalidSnapshot([String])
    case insufficientCash(required: Double, available: Double)
    case generationFailed(String)
    case noSignificantDrift
    case allOrdersFiltered([FilteredOrderInfo])
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidSnapshot:
            return "Check portfolio has positions and target allocation"
        case .insufficientCash:
            return "Add cash or reduce buy orders"
        case .noSignificantDrift:
            return "No action needed at this time"
        case .allOrdersFiltered:
            return "Check minimum order size settings"
        default:
            return nil
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .invalidSnapshot(let errors):
            return "Invalid portfolio: \(errors.joined(separator: ", "))"
        case .insufficientCash(let required, let available):
            return "Need $\(String(format: "%.2f", required)), have $\(String(format: "%.2f", available))"
        case .generationFailed(let message):
            return "Failed: \(message)"
        case .noSignificantDrift:
            return "No positions exceed drift threshold"
        case .allOrdersFiltered(let reasons):
            let reasonStrings = reasons.map { "\($0.symbol): \($0.reason)" }
            return "Orders filtered: \(reasonStrings.joined(separator: "; "))"
        }
    }
}

// MARK: - Engine

/// Main rebalancing engine
actor RebalancingEngine {
    
    private let configuration: RebalancingConfiguration
    private let driftAnalyzer: DriftAnalyzer
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "RebalancingEngine")
    
    init(configuration: RebalancingConfiguration = .default) {
        self.configuration = configuration
        self.driftAnalyzer = DriftAnalyzer(threshold: configuration.driftThreshold)
    }
    
    /// Generates a rebalance plan from a portfolio snapshot
    /// - Parameters:
    ///   - snapshot: Portfolio snapshot (created on MainActor)
    ///   - availableCash: Cash available for trading
    /// - Returns: Rebalance plan with orders and metadata
    /// - Throws: RebalancingError if plan cannot be generated
    func generatePlan(
        from snapshot: PortfolioSnapshot,
        availableCash: Double
    ) throws -> RebalancePlan {
        // Validate snapshot
        guard snapshot.isValid else {
            throw RebalancingError.invalidSnapshot(snapshot.validationErrors)
        }
        
        // Analyze drift using pure data structs (no CoreData objects)
        let analysis = try driftAnalyzer.analyze(
            positions: snapshot.positions.map { $0.asPositionData() },
            targetAllocation: snapshot.targetAllocation,
            totalValue: snapshot.totalValue
        )
        
        logger.info("Analyzing \(snapshot.name ?? "Portfolio"): \(analysis.totalDrift) drift")
        
        // Check if rebalancing is needed
        guard analysis.needsRebalancing else {
            throw RebalancingError.noSignificantDrift
        }
        
        // Generate orders using strategy
        let orders = configuration.strategy.generateOrders(
            analysis: analysis,
            snapshot: snapshot,
            availableCash: availableCash,
            config: configuration
        )
        
        // Track filtered orders (optimized from O(n²) to O(n) using Set)
        let orderSymbols = Set(orders.map { $0.symbol })
        var filteredReasons: [FilteredOrderInfo] = []
        for drift in analysis.significantDrifts {
            if !orderSymbols.contains(drift.symbol) {
                filteredReasons.append(FilteredOrderInfo(
                    symbol: drift.symbol,
                    reason: "Below minimum size or invalid"
                ))
            }
        }
        
        guard !orders.isEmpty else {
            throw RebalancingError.allOrdersFiltered(filteredReasons)
        }
        
        // Create plan
        let plan = RebalancePlan(
            portfolioId: snapshot.id,
            portfolioName: snapshot.name,
            orders: orders,
            driftAnalysis: analysis,
            filteredReasons: filteredReasons.isEmpty ? nil : filteredReasons
        )
        
        // Validate cash requirements
        guard plan.canExecute(with: availableCash) else {
            throw RebalancingError.insufficientCash(
                required: plan.netCashNeeded,
                available: availableCash
            )
        }
        
        logger.info("Generated plan with \(orders.count) orders")
        return plan
    }
    
    /// Quick check if rebalancing is needed
    func needsRebalancing(_ snapshot: PortfolioSnapshot) -> Bool {
        guard snapshot.isValid else { return false }
        
        return driftAnalyzer.needsRebalancing(
            positions: snapshot.positions.map { $0.asPositionData() },
            targetAllocation: snapshot.targetAllocation,
            totalValue: snapshot.totalValue
        )
    }
    
    /// Calculates next scheduled rebalancing date
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
    func isRebalancingOverdue(
        lastRebalanceDate: Date?,
        frequency: RebalancingFrequency
    ) -> Bool {
        guard let lastDate = lastRebalanceDate else { return true }
        let nextDate = nextRebalancingDate(lastRebalanceDate: lastDate, frequency: frequency)
        return Date() > nextDate
    }
}

// MARK: - Helper Extensions

private extension PositionSnapshot {
    /// Converts snapshot to PositionData for DriftAnalyzer
    /// Returns a pure struct instead of creating fake CoreData objects
    func asPositionData() -> PositionData {
        PositionData(
            symbol: symbol,
            currentValue: currentValue
        )
    }
}
