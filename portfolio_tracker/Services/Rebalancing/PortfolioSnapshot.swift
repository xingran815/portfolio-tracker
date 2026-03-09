//
//  PortfolioSnapshot.swift
//  portfolio_tracker
//
//  Snapshot of portfolio data for thread-safe access
//

import Foundation

/// Immutable snapshot of portfolio data for safe cross-actor access
struct PortfolioSnapshot: Sendable {
    let id: UUID?
    let name: String?
    let positions: [PositionSnapshot]
    let targetAllocation: [String: Double]
    let totalValue: Double
    let rebalancingFrequency: RebalancingFrequency
    let lastRebalancedAt: Date?
    
    /// Creates a snapshot from a Portfolio (must be called on MainActor)
    static func from(_ portfolio: Portfolio) -> PortfolioSnapshot {
        let positionSet = portfolio.positions as? Set<Position> ?? []
        let positionSnapshots = positionSet.map { PositionSnapshot.from($0) }
        
        return PortfolioSnapshot(
            id: portfolio.id,
            name: portfolio.name,
            positions: Array(positionSnapshots),
            targetAllocation: portfolio.targetAllocation,
            totalValue: portfolio.totalValue,
            rebalancingFrequency: portfolio.rebalancingFrequency,
            lastRebalancedAt: portfolio.updatedAt
        )
    }
}

/// Immutable snapshot of position data
/// Conforms to PositionProtocol for use with DriftAnalyzer
struct PositionSnapshot: Sendable, PositionProtocol {
    let id: UUID?
    let symbol: String?
    let name: String?
    let shares: Double
    let costBasis: Double
    let currentPrice: Double
    let currentValue: Double?
    let profitLoss: Double?
    let profitLossPercentage: Double?
    let assetType: AssetType
    let market: Market
    let lastUpdated: Date?
    
    /// Creates a snapshot from a Position (must be called on MainActor)
    static func from(_ position: Position) -> PositionSnapshot {
        PositionSnapshot(
            id: position.id,
            symbol: position.symbol,
            name: position.name,
            shares: position.shares,
            costBasis: position.costBasis,
            currentPrice: position.currentPrice,
            currentValue: position.currentValue,
            profitLoss: position.profitLoss,
            profitLossPercentage: position.profitLossPercentage,
            assetType: position.assetType,
            market: position.market,
            lastUpdated: position.lastUpdated
        )
    }
}

// MARK: - PositionData (Pure Business Logic)

/// Pure data struct for position analysis
/// Used when creating positions from snapshots without CoreData
struct PositionData: Sendable, PositionProtocol {
    let symbol: String?
    let currentValue: Double?
    
    init(symbol: String?, currentValue: Double?) {
        self.symbol = symbol
        self.currentValue = currentValue
    }
}

// MARK: - Validation

extension PortfolioSnapshot {
    
    /// Validates the snapshot is usable for rebalancing
    var isValid: Bool {
        !positions.isEmpty &&
        !targetAllocation.isEmpty &&
        totalValue > 0 &&
        targetAllocation.values.reduce(0, +) > 0
    }
    
    /// Validation errors if any
    nonisolated var validationErrors: [String] {
        var errors: [String] = []
        
        if positions.isEmpty {
            errors.append("Portfolio has no positions")
        }
        
        if targetAllocation.isEmpty {
            errors.append("No target allocation set")
        }
        
        if totalValue <= 0 {
            errors.append("Portfolio has no value")
        }
        
        let targetTotal = targetAllocation.values.reduce(0, +)
        if targetTotal <= 0 {
            errors.append("Target allocation sums to zero")
        }
        
        return errors
    }
}

// MARK: - Convenience

extension PortfolioSnapshot {
    
    /// Total cost basis of all positions
    var totalCost: Double {
        positions.reduce(0) { $0 + ($1.costBasis * $1.shares) }
    }
    
    /// Total profit/loss
    var totalProfitLoss: Double {
        totalValue - totalCost
    }
    
    /// Position for a specific symbol
    func position(for symbol: String) -> PositionSnapshot? {
        positions.first { $0.symbol == symbol }
    }
    
    /// Weight of a specific position
    func weight(for symbol: String) -> Double {
        guard totalValue > 0 else { return 0 }
        let value = position(for: symbol)?.currentValue ?? 0
        return value / totalValue
    }
}
