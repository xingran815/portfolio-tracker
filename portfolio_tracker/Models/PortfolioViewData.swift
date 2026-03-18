//
//  PortfolioViewData.swift
//  portfolio_tracker
//
//  View-safe data model for portfolio display
//

import Foundation

/// Immutable data structure for portfolio display in Views.
/// This is a lightweight, Sendable alternative to Portfolio (NSManagedObject)
/// that can be safely passed across actor boundaries.
struct PortfolioViewData: Identifiable, Sendable {
    let id: UUID
    let name: String
    let riskProfile: RiskProfile
    let rebalancingFrequency: RebalancingFrequency
    let totalValue: Double
    let totalCost: Double
    let totalProfitLoss: Double
    let profitLossPercentage: Double
    let positionCount: Int
    let lastUpdated: Date?
    let targetAllocation: [String: Double]
    
    /// Creates view data from a Portfolio (must be called on MainActor)
    static func from(_ portfolio: Portfolio) -> PortfolioViewData {
        PortfolioViewData(
            id: portfolio.id ?? UUID(),
            name: portfolio.name ?? "未命名",
            riskProfile: portfolio.riskProfile,
            rebalancingFrequency: portfolio.rebalancingFrequency,
            totalValue: portfolio.totalValue,
            totalCost: portfolio.totalCost,
            totalProfitLoss: portfolio.totalProfitLoss,
            profitLossPercentage: portfolio.profitLossPercentage,
            positionCount: (portfolio.positions as? Set<Position>)?.count ?? 0,
            lastUpdated: portfolio.updatedAt,
            targetAllocation: portfolio.targetAllocation
        )
    }
}

/// Immutable data structure for position display in Views
struct PositionViewData: Identifiable, Sendable {
    let id: UUID
    let symbol: String
    let name: String
    let assetType: AssetType
    let market: Market
    let shares: Double
    let costBasis: Double
    let currentPrice: Double
    let currentValue: Double
    let profitLoss: Double
    let profitLossPercentage: Double
    let weightInPortfolio: Double
    let lastUpdated: Date?
    
    /// Creates view data from a Position (must be called on MainActor)
    static func from(_ position: Position, totalPortfolioValue: Double) -> PositionViewData {
        let value = position.currentValue ?? 0
        let weight = totalPortfolioValue > 0 ? value / totalPortfolioValue : 0
        
        return PositionViewData(
            id: position.id ?? UUID(),
            symbol: position.symbol ?? "-",
            name: position.name ?? "",
            assetType: position.assetType,
            market: position.market,
            shares: position.shares,
            costBasis: position.costBasis,
            currentPrice: position.currentPrice,
            currentValue: value,
            profitLoss: position.profitLoss ?? 0,
            profitLossPercentage: position.profitLossPercentage ?? 0,
            weightInPortfolio: weight,
            lastUpdated: position.lastUpdated
        )
    }
}

// MARK: - Convenience Extensions

extension PortfolioViewData {
    /// Returns true if portfolio has positions
    var hasPositions: Bool {
        positionCount > 0
    }
    
    /// Returns formatted display string
    var displayTitle: String {
        name
    }
    
    /// Returns subtitle with value and position count
    var displaySubtitle: String {
        "\(totalValue.formattedAsCurrency()) · \(positionCount) 持仓"
    }
}
