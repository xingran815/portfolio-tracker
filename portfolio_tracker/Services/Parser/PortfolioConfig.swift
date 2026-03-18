//
//  PortfolioConfig.swift
//  portfolio_tracker
//
//  Data structures for parsed portfolio configuration
//

import Foundation

/// Parsed portfolio configuration from Markdown
struct PortfolioConfig: Sendable {
    /// Portfolio name (required)
    let name: String
    
    /// Risk profile (optional, defaults to moderate)
    let riskProfile: RiskProfile?
    
    /// Expected annual return as decimal (e.g., 0.08 for 8%)
    let expectedReturn: Double?
    
    /// Maximum acceptable drawdown as decimal (e.g., 0.15 for 15%)
    let maxDrawdown: Double?
    
    /// Rebalancing frequency (optional, defaults to quarterly)
    let rebalancingFrequency: RebalancingFrequency?
    
    /// Target allocation map [symbol: percentage] (e.g., ["AAPL": 0.4])
    let targetAllocation: [String: Double]?
    
    /// Positions in the portfolio
    let positions: [PositionConfig]
}

/// Parsed position configuration
struct PositionConfig: Sendable {
    /// Stock symbol (required, e.g., "AAPL", "0700.HK")
    let symbol: String
    
    /// Company/fund name (optional)
    let name: String?
    
    /// Asset type (optional, defaults based on configuration)
    let assetType: AssetType?
    
    /// Market identifier (optional, inferred from symbol if possible)
    let market: Market?
    
    /// Number of shares/units (required)
    let shares: Double
    
    /// Cost basis per share (optional)
    let costBasis: Double?
    
    /// Currency code (optional, inferred from market)
    var currency: String? {
        market?.currency
    }
}

// MARK: - Convenience Properties

extension PortfolioConfig {
    /// Total shares count across all positions
    var totalPositions: Int {
        positions.count
    }
    
    /// Whether this configuration has target allocation defined
    var hasTargetAllocation: Bool {
        guard let allocation = targetAllocation else { return false }
        return !allocation.isEmpty
    }
    
    /// Total target allocation percentage (should be close to 1.0 if valid)
    var totalTargetAllocation: Double {
        targetAllocation?.values.reduce(0, +) ?? 0
    }
    
    /// Whether target allocation sums to approximately 100%
    var isTargetAllocationValid: Bool {
        let total = totalTargetAllocation
        return total >= 0.99 && total <= 1.01
    }
}

extension PositionConfig {
    /// Total cost for this position
    var totalCost: Double {
        guard let costBasis = costBasis else { return 0 }
        return shares * costBasis
    }
    
    /// Formatted symbol with market indicator
    var displaySymbol: String {
        if let market = market, !symbol.hasSuffix(".\(market.rawValue)") {
            return "\(symbol).\(market.rawValue)"
        }
        return symbol
    }
}
