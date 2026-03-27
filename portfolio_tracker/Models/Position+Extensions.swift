//
//  Position+Extensions.swift
//  portfolio_tracker
//
//  Position model extensions
//

import CoreData
import Foundation

// MARK: - PositionProtocol Conformance

extension Position: PositionProtocol {}

// MARK: - Position Entity Extension
extension Position {
    
    /// Asset type as enum
    public var assetType: AssetType {
        get {
            AssetType(rawValue: assetTypeRaw ?? AssetType.stock.rawValue) ?? .stock
        }
        set {
            assetTypeRaw = newValue.rawValue
        }
    }
    
    /// Market as enum
    public var market: Market {
        get {
            Market(rawValue: marketRaw ?? Market.us.rawValue) ?? .us
        }
        set {
            marketRaw = newValue.rawValue
        }
    }
    
    /// Currency as enum
    public var currencyEnum: Currency {
        get {
            Currency(rawValue: currency ?? Currency.cny.rawValue) ?? .cny
        }
        set {
            currency = newValue.rawValue
        }
    }
    
    /// Entry mode as enum
    public var entryMode: EntryMode {
        get {
            EntryMode(rawValue: entryModeRaw ?? EntryMode.shares.rawValue) ?? .shares
        }
        set {
            entryModeRaw = newValue.rawValue
        }
    }
    
    /// Current market value (price * shares)
    public var currentValue: Double? {
        if assetType == .cash {
            return totalCost
        }
        guard currentPrice > 0 else { return nil }
        return currentPrice * shares
    }
    
    /// Cost basis total (cost per share * shares)
    public var totalCost: Double {
        return costBasis * shares
    }
    
    /// Profit/loss amount
    public var profitLoss: Double? {
        guard let value = currentValue else { return nil }
        return value - totalCost
    }
    
    /// Profit/loss percentage
    public var profitLossPercentage: Double? {
        guard totalCost > 0, let profit = profitLoss else { return nil }
        return profit / totalCost
    }
    
    /// Weight in portfolio (if assigned to portfolio)
    public var weightInPortfolio: Double? {
        guard let portfolio = portfolio, portfolio.totalValue > 0,
              let value = currentValue else { return nil }
        return value / portfolio.totalValue
    }
}

// MARK: - Convenience Methods

extension Position {
    
    /// Creates a new position
    /// - Parameters:
    ///   - context: NSManagedObjectContext
    ///   - symbol: Stock/fund symbol
    ///   - name: Display name
    ///   - assetType: Type of asset
    ///   - market: Market identifier
    ///   - shares: Number of shares/units
    ///   - costBasis: Cost per share
    ///   - portfolio: Parent portfolio (optional)
    /// - Returns: New position instance
    @discardableResult
    public static func create(
        in context: NSManagedObjectContext,
        symbol: String,
        name: String,
        assetType: AssetType,
        market: Market,
        shares: Double,
        costBasis: Double,
        currency: Currency? = nil,
        entryMode: EntryMode = .shares,
        initialPrice: Double = 0,
        portfolio: Portfolio? = nil
    ) -> Position {
        let position = Position(context: context)
        position.id = UUID()
        position.symbol = symbol.uppercased()
        position.name = name
        position.assetTypeRaw = assetType.rawValue
        position.marketRaw = market.rawValue
        position.shares = shares
        position.costBasis = costBasis
        position.currentPrice = initialPrice
        position.currency = currency?.rawValue ?? market.currency
        position.entryModeRaw = entryMode.rawValue
        position.lastUpdated = initialPrice > 0 ? Date() : nil
        position.portfolio = portfolio
        return position
    }
    
    /// Updates current price
    /// - Parameters:
    ///   - price: New price
    ///   - date: Update timestamp
    public func updatePrice(_ price: Double, at date: Date = Date()) {
        currentPrice = price
        lastUpdated = date
        portfolio?.updatedAt = date
    }
}
