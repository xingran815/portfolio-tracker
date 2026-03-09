//
//  RebalancePlan.swift
//  portfolio_tracker
//
//  Rebalance plan model with buy/sell orders
//

import Foundation

// MARK: - Order Types

enum OrderAction: String, Sendable, CaseIterable {
    case buy
    case sell
    
    var displayName: String {
        switch self {
        case .buy: return "Buy"
        case .sell: return "Sell"
        }
    }
}

enum OrderPriority: Int, Sendable, Comparable {
    case high = 3
    case medium = 2
    case low = 1
    
    static func < (lhs: OrderPriority, rhs: OrderPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

// MARK: - Order

struct RebalanceOrder: Identifiable, Sendable {
    let id: UUID
    let symbol: String
    let action: OrderAction
    let shares: Double
    let estimatedPrice: Double
    let estimatedAmount: Double
    let priority: OrderPriority
    let reason: String
    let notes: String?
    
    init(
        id: UUID = UUID(),
        symbol: String,
        action: OrderAction,
        shares: Double,
        estimatedPrice: Double,
        priority: OrderPriority = .medium,
        reason: String,
        notes: String? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.action = action
        self.shares = shares
        self.estimatedPrice = estimatedPrice
        self.estimatedAmount = shares * estimatedPrice
        self.priority = priority
        self.reason = reason
        self.notes = notes
    }
    
    func withHighPriority() -> RebalanceOrder {
        RebalanceOrder(
            id: id,
            symbol: symbol,
            action: action,
            shares: shares,
            estimatedPrice: estimatedPrice,
            priority: .high,
            reason: reason,
            notes: notes
        )
    }
}

// MARK: - Filtered Reason Info

struct FilteredOrderInfo: Sendable {
    let symbol: String
    let reason: String
}

// MARK: - Plan

struct RebalancePlan: Identifiable, Sendable {
    let id: UUID
    let portfolioId: UUID?
    let portfolioName: String?
    let createdAt: Date
    let status: PlanStatus
    
    let orders: [RebalanceOrder]
    let driftAnalysis: DriftAnalysis?
    let filteredReasons: [FilteredOrderInfo]?
    
    let totalBuyAmount: Double
    let totalSellAmount: Double
    
    var netCashNeeded: Double {
        totalBuyAmount - totalSellAmount
    }
    
    let estimatedTaxImpact: Double?
    let notes: String?
    
    init(
        id: UUID = UUID(),
        portfolioId: UUID? = nil,
        portfolioName: String? = nil,
        createdAt: Date = Date(),
        status: PlanStatus = .draft,
        orders: [RebalanceOrder],
        driftAnalysis: DriftAnalysis? = nil,
        filteredReasons: [FilteredOrderInfo]? = nil,
        estimatedTaxImpact: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.portfolioId = portfolioId
        self.portfolioName = portfolioName
        self.createdAt = createdAt
        self.status = status
        self.orders = orders
        self.driftAnalysis = driftAnalysis
        self.filteredReasons = filteredReasons
        self.totalBuyAmount = orders.filter { $0.action == .buy }.reduce(0) { $0 + $1.estimatedAmount }
        self.totalSellAmount = orders.filter { $0.action == .sell }.reduce(0) { $0 + $1.estimatedAmount }
        self.estimatedTaxImpact = estimatedTaxImpact
        self.notes = notes
    }
}

// MARK: - Extensions

extension RebalancePlan {
    
    var buyOrders: [RebalanceOrder] {
        orders.filter { $0.action == .buy }
    }
    
    var sellOrders: [RebalanceOrder] {
        orders.filter { $0.action == .sell }
    }
    
    var prioritizedOrders: [RebalanceOrder] {
        orders.sorted { $0.priority > $1.priority }
    }
    
    var orderCount: Int {
        orders.count
    }
    
    var hasFilteredOrders: Bool {
        !(filteredReasons?.isEmpty ?? true)
    }
    
    func canExecute(with availableCash: Double) -> Bool {
        guard netCashNeeded > 0 else { return true }
        return availableCash >= netCashNeeded
    }
    
    func markAsExecuted() -> RebalancePlan {
        RebalancePlan(
            id: id,
            portfolioId: portfolioId,
            portfolioName: portfolioName,
            createdAt: createdAt,
            status: .executed,
            orders: orders,
            driftAnalysis: driftAnalysis,
            filteredReasons: filteredReasons,
            estimatedTaxImpact: estimatedTaxImpact,
            notes: notes
        )
    }
    
    func markAsCancelled(reason: String? = nil) -> RebalancePlan {
        let combinedNotes: String
        if let existing = notes, let new = reason {
            combinedNotes = "\(existing)\nCancelled: \(new)"
        } else {
            combinedNotes = reason ?? notes ?? ""
        }
        
        return RebalancePlan(
            id: id,
            portfolioId: portfolioId,
            portfolioName: portfolioName,
            createdAt: createdAt,
            status: .cancelled,
            orders: orders,
            driftAnalysis: driftAnalysis,
            filteredReasons: filteredReasons,
            estimatedTaxImpact: estimatedTaxImpact,
            notes: combinedNotes
        )
    }
    
    var summary: String {
        var lines: [String] = []
        lines.append("Rebalance Plan: \(portfolioName ?? "Portfolio")")
        lines.append("Status: \(status.displayName)")
        lines.append("Created: \(createdAt.formatted(date: .abbreviated, time: .shortened))")
        
        if !orders.isEmpty {
            lines.append("")
            lines.append("Orders (\(orderCount)):")
            for order in prioritizedOrders {
                let amount = String(format: "%.2f", order.estimatedAmount)
                lines.append("- \(order.action.displayName) \(order.shares) \(order.symbol) ($\(amount))")
            }
        }
        
        lines.append("")
        lines.append("Totals:")
        lines.append("- Buy: $\(String(format: "%.2f", totalBuyAmount))")
        lines.append("- Sell: $\(String(format: "%.2f", totalSellAmount))")
        lines.append("- Net Cash: $\(String(format: "%.2f", netCashNeeded))")
        
        if let reasons = filteredReasons, !reasons.isEmpty {
            lines.append("")
            lines.append("Filtered (\(reasons.count)):")
            for reason in reasons {
                lines.append("- \(reason.symbol): \(reason.reason)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}

extension RebalanceOrder {
    var displayString: String {
        let amount = String(format: "%.2f", estimatedAmount)
        let shareStr = String(format: "%.0f", shares)
        return "\(action.displayName) \(shareStr) \(symbol) ($\(amount))"
    }
}

// MARK: - Validation

struct RebalancePlanValidator {
    
    static func validate(_ plan: RebalancePlan) -> [String] {
        var issues: [String] = []
        
        if plan.orders.isEmpty {
            issues.append("Plan has no orders")
        }
        
        for order in plan.orders {
            if order.shares <= 0 {
                issues.append("\(order.symbol): Invalid share count \(order.shares)")
            }
            if order.estimatedPrice <= 0 {
                issues.append("\(order.symbol): Invalid price \(order.estimatedPrice)")
            }
        }
        
        // Check for extreme skew
        let total = plan.totalBuyAmount + plan.totalSellAmount
        if total > 0 {
            let buyRatio = plan.totalBuyAmount / total
            if buyRatio > 0.9 {
                issues.append("Plan heavily skewed toward buying (\(Int(buyRatio * 100))%)")
            } else if buyRatio < 0.1 {
                issues.append("Plan heavily skewed toward selling (\(Int((1-buyRatio) * 100))%)")
            }
        }
        
        return issues
    }
    
    static func isValid(_ plan: RebalancePlan) -> Bool {
        validate(plan).isEmpty
    }
}
