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
    
    /// Currency for portfolio display
    public var currency: Currency {
        get {
            Currency(rawValue: currencyRaw ?? Currency.cny.rawValue) ?? .cny
        }
        set {
            currencyRaw = newValue.rawValue
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
    
    /// Total market value converted to target currency using provided rates
    /// - Parameters:
    ///   - targetCurrency: Target currency for conversion
    ///   - rates: Exchange rates dictionary from base currency (e.g., USD)
    /// - Returns: Total value in target currency
    public func totalValueIn(currency targetCurrency: Currency, rates: [String: Double]) -> Double {
        guard let positions = positions as? Set<Position> else { return 0 }
        
        return positions.reduce(0) { sum, position in
            guard let value = position.currentValue else { return sum }
            let positionCurrency = position.currencyEnum
            
            if positionCurrency == targetCurrency {
                return sum + value
            }
            
            guard let fromRate = rates[positionCurrency.code],
                  let toRate = rates[targetCurrency.code] else {
                return sum + value
            }
            
            return sum + value * (toRate / fromRate)
        }
    }
    
    /// Total cost converted to target currency using provided rates
    public func totalCostIn(currency targetCurrency: Currency, rates: [String: Double]) -> Double {
        guard let positions = positions as? Set<Position> else { return 0 }
        
        return positions.reduce(0) { sum, position in
            let cost = position.totalCost
            let positionCurrency = position.currencyEnum
            
            if positionCurrency == targetCurrency {
                return sum + cost
            }
            
            guard let fromRate = rates[positionCurrency.code],
                  let toRate = rates[targetCurrency.code] else {
                return sum + cost
            }
            
            return sum + cost * (toRate / fromRate)
        }
    }
    
    /// Total profit/loss converted to target currency
    public func totalProfitLossIn(currency targetCurrency: Currency, rates: [String: Double]) -> Double {
        totalValueIn(currency: targetCurrency, rates: rates) - totalCostIn(currency: targetCurrency, rates: rates)
    }
    
    /// Total market value converted to target currency using provided rates and positions array
    public func totalValueIn(currency targetCurrency: Currency, rates: [String: Double], positions: [Position]) -> Double {
        positions.reduce(0) { sum, position in
            guard let value = position.currentValue else { return sum }
            let positionCurrency = position.currencyEnum
            
            if positionCurrency == targetCurrency {
                return sum + value
            }
            
            guard let fromRate = rates[positionCurrency.code],
                  let toRate = rates[targetCurrency.code] else {
                return sum + value
            }
            
            return sum + value * (toRate / fromRate)
        }
    }
    
    /// Total cost converted to target currency using provided rates and positions array
    public func totalCostIn(currency targetCurrency: Currency, rates: [String: Double], positions: [Position]) -> Double {
        positions.reduce(0) { sum, position in
            let cost = position.totalCost
            let positionCurrency = position.currencyEnum
            
            if positionCurrency == targetCurrency {
                return sum + cost
            }
            
            guard let fromRate = rates[positionCurrency.code],
                  let toRate = rates[targetCurrency.code] else {
                return sum + cost
            }
            
            return sum + cost * (toRate / fromRate)
        }
    }
    
    /// Total profit/loss converted to target currency using positions array
    public func totalProfitLossIn(currency targetCurrency: Currency, rates: [String: Double], positions: [Position]) -> Double {
        totalValueIn(currency: targetCurrency, rates: rates, positions: positions) - totalCostIn(currency: targetCurrency, rates: rates, positions: positions)
    }
}

// MARK: - Convenience Methods

extension Portfolio {
    
    /// Creates a new portfolio with default values
    /// - Parameters:
    ///   - context: NSManagedObjectContext
    ///   - name: Portfolio name
    ///   - riskProfile: Risk tolerance
    ///   - currency: Portfolio base currency (default: CNY)
    /// - Returns: New portfolio instance
    @discardableResult
    public static func create(
        in context: NSManagedObjectContext,
        name: String,
        riskProfile: RiskProfile = .moderate,
        currency: Currency = .cny
    ) -> Portfolio {
        let portfolio = Portfolio(context: context)
        portfolio.id = UUID()
        portfolio.name = name
        portfolio.riskProfileRaw = riskProfile.rawValue
        portfolio.currencyRaw = currency.rawValue
        portfolio.expectedReturn = 0.08
        portfolio.maxDrawdown = 0.15
        portfolio.rebalancingFrequencyRaw = RebalancingFrequency.quarterly.rawValue
        portfolio.targetAllocationData = nil
        portfolio.createdAt = Date()
        portfolio.updatedAt = Date()
        return portfolio
    }
}
