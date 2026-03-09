//
//  Portfolio+Extensions.swift
//  portfolio_tracker
//
//  Portfolio model extensions
//

import CoreData
import Foundation

// MARK: - Portfolio Entity Extension
extension Portfolio {
    
    /// Risk profile as enum type
    public var riskProfile: RiskProfile {
        get {
            RiskProfile(rawValue: riskProfileRaw ?? RiskProfile.moderate.rawValue) ?? .moderate
        }
        set {
            riskProfileRaw = newValue.rawValue
        }
    }
    
    /// Rebalancing frequency as enum type
    public var rebalancingFrequency: RebalancingFrequency {
        get {
            RebalancingFrequency(rawValue: rebalancingFrequencyRaw ?? RebalancingFrequency.quarterly.rawValue) ?? .quarterly
        }
        set {
            rebalancingFrequencyRaw = newValue.rawValue
        }
    }
    
    /// Target allocation as dictionary [symbol: percentage]
    public var targetAllocation: [String: Double] {
        get {
            guard let data = targetAllocationData,
                  let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
                return [:]
            }
            return dict
        }
        set {
            targetAllocationData = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Total market value of all positions
    public var totalValue: Double {
        (positions as? Set<Position>)?.reduce(0) { $0 + ($1.currentValue ?? 0) } ?? 0
    }
    
    /// Total cost basis
    public var totalCost: Double {
        (positions as? Set<Position>)?.reduce(0) { $0 + $1.totalCost } ?? 0
    }
    
    /// Total profit/loss
    public var totalProfitLoss: Double {
        totalValue - totalCost
    }
    
    /// Profit/loss percentage
    public var profitLossPercentage: Double {
        guard totalCost > 0 else { return 0 }
        return totalProfitLoss / totalCost
    }
}

// MARK: - Convenience Methods

extension Portfolio {
    
    /// Creates a new portfolio with default values
    /// - Parameters:
    ///   - context: NSManagedObjectContext
    ///   - name: Portfolio name
    ///   - riskProfile: Risk tolerance
    /// - Returns: New portfolio instance
    @discardableResult
    public static func create(
        in context: NSManagedObjectContext,
        name: String,
        riskProfile: RiskProfile = .moderate
    ) -> Portfolio {
        let portfolio = Portfolio(context: context)
        portfolio.id = UUID()
        portfolio.name = name
        portfolio.riskProfileRaw = riskProfile.rawValue
        portfolio.expectedReturn = 0.08
        portfolio.maxDrawdown = 0.15
        portfolio.rebalancingFrequencyRaw = RebalancingFrequency.quarterly.rawValue
        portfolio.targetAllocationData = nil
        portfolio.createdAt = Date()
        portfolio.updatedAt = Date()
        return portfolio
    }
}
