//
//  Transaction+Extensions.swift
//  portfolio_tracker
//
//  Transaction model extensions
//

import CoreData
import Foundation

// MARK: - Transaction Entity Extension
extension Transaction {
    
    /// Transaction type as enum
    public var type: TransactionType {
        get {
            TransactionType(rawValue: typeRaw ?? TransactionType.buy.rawValue) ?? .buy
        }
        set {
            typeRaw = newValue.rawValue
        }
    }
    
    /// Net amount (amount - fees for buy, amount + fees for sell)
    public var netAmount: Double {
        switch type {
        case .buy:
            return amount + fees
        case .sell, .dividend:
            return amount - fees
        }
    }
}

// MARK: - Convenience Methods

extension Transaction {
    
    /// Creates a new transaction
    /// - Parameters:
    ///   - context: NSManagedObjectContext
    ///   - type: Transaction type
    ///   - symbol: Stock/fund symbol
    ///   - shares: Number of shares
    ///   - price: Price per share
    ///   - fees: Transaction fees
    ///   - date: Transaction date
    ///   - portfolio: Parent portfolio
    ///   - notes: Optional notes
    /// - Returns: New transaction instance
    @discardableResult
    public static func create(
        in context: NSManagedObjectContext,
        type: TransactionType,
        symbol: String,
        shares: Double,
        price: Double,
        fees: Double = 0,
        date: Date = Date(),
        portfolio: Portfolio? = nil,
        notes: String? = nil
    ) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.typeRaw = type.rawValue
        transaction.symbol = symbol.uppercased()
        transaction.shares = shares
        transaction.price = price
        transaction.amount = shares * price
        transaction.fees = fees
        transaction.date = date
        transaction.notes = notes
        transaction.portfolio = portfolio
        return transaction
    }
    
    /// Creates a buy transaction and updates position
    /// - Returns: Created transaction
    @discardableResult
    public static func recordBuy(
        in context: NSManagedObjectContext,
        symbol: String,
        shares: Double,
        price: Double,
        fees: Double = 0,
        portfolio: Portfolio,
        date: Date = Date()
    ) -> Transaction {
        let transaction = create(
            in: context,
            type: .buy,
            symbol: symbol,
            shares: shares,
            price: price,
            fees: fees,
            date: date,
            portfolio: portfolio
        )
        
        // Update or create position
        if let position = (portfolio.positions as? Set<Position>)?.first(where: { $0.symbol == symbol }) {
            let totalShares = position.shares + shares
            let totalCost = (position.shares * position.costBasis) + (shares * price)
            position.shares = totalShares
            position.costBasis = totalCost / totalShares
        }
        
        portfolio.updatedAt = Date()
        return transaction
    }
    
    /// Creates a sell transaction and updates position
    @discardableResult
    public static func recordSell(
        in context: NSManagedObjectContext,
        symbol: String,
        shares: Double,
        price: Double,
        fees: Double = 0,
        portfolio: Portfolio,
        date: Date = Date()
    ) -> Transaction? {
        guard let position = (portfolio.positions as? Set<Position>)?.first(where: { $0.symbol == symbol }),
              position.shares >= shares else {
            return nil
        }
        
        let transaction = create(
            in: context,
            type: .sell,
            symbol: symbol,
            shares: shares,
            price: price,
            fees: fees,
            date: date,
            portfolio: portfolio
        )
        
        position.shares -= shares
        
        // Remove position if fully sold
        if position.shares == 0 {
            context.delete(position)
        }
        
        portfolio.updatedAt = Date()
        return transaction
    }
}
