//
//  RebalancePlan.swift
//  portfolio_tracker
//
//  Rebalance plan model with buy/sell orders
//

import Foundation

/// Action type for rebalance orders
enum OrderAction: String, Codable, Sendable, CaseIterable {
    case buy
    case sell
    
    var displayName: String {
        switch self {
        case .buy: return "Buy"
        case .sell: return "Sell"
        }
    }
    
    var sign: Double {
        switch self {
        case .buy: return 1
        case .sell: return -1
        }
    }
}

/// Priority level for order execution
enum OrderPriority: Int, Codable, Sendable, Comparable {
    case high = 3
    case medium = 2
    case low = 1
    
    static func < (lhs: OrderPriority, rhs: OrderPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Individual rebalance order
struct RebalanceOrder: Identifiable, Codable, Sendable {
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
}

/// Complete rebalance plan
struct RebalancePlan: Identifiable, Codable, Sendable {
    let id: UUID
    let portfolioId: UUID?
    let portfolioName: String?
    let createdAt: Date
    let status: PlanStatus
    
    /// Orders to execute
    let orders: [RebalanceOrder]
    
    /// Analysis that generated this plan
    let driftAnalysis: DriftAnalysis?
    
    /// Total buy amount
    let totalBuyAmount: Double
    
    /// Total sell amount
    let totalSellAmount: Double
    
    /// Net cash needed (negative = cash generated)
    var netCashNeeded: Double {
        totalBuyAmount - totalSellAmount
    }
    
    /// Estimated tax impact (if available)
    let estimatedTaxImpact: Double?
    
    /// Notes about the plan
    let notes: String?
    
    init(
        id: UUID = UUID(),
        portfolioId: UUID? = nil,
        portfolioName: String? = nil,
        createdAt: Date = Date(),
        status: PlanStatus = .draft,
        orders: [RebalanceOrder],
        driftAnalysis: DriftAnalysis? = nil,
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
        self.totalBuyAmount = orders.filter { $0.action == .buy }.reduce(0) { $0 + $1.estimatedAmount }
        self.totalSellAmount = orders.filter { $0.action == .sell }.reduce(0) { $0 + $1.estimatedAmount }
        self.estimatedTaxImpact = estimatedTaxImpact
        self.notes = notes
    }
}

/// Strategy for order execution
enum ExecutionStrategy: String, Codable, Sendable, CaseIterable {
    /// Execute all orders at once
    case immediate
    
    /// Execute in batches by priority
    case byPriority
    
    /// Execute sells first, then buys
    case sellFirst
    
    /// Execute largest orders first
    case largestFirst
    
    var displayName: String {
        switch self {
        case .immediate: return "Immediate"
        case .byPriority: return "By Priority"
        case .sellFirst: return "Sell First"
        case .largestFirst: return "Largest First"
        }
    }
    
    var description: String {
        switch self {
        case .immediate:
            return "Execute all orders simultaneously"
        case .byPriority:
            return "Execute high priority orders first"
        case .sellFirst:
            return "Sell overweight positions first to generate cash"
        case .largestFirst:
            return "Execute largest orders first for maximum impact"
        }
    }
}

/// Execution schedule for rebalancing
struct RebalanceSchedule: Sendable {
    /// Target execution date
    let targetDate: Date
    
    /// Execution strategy
    let strategy: ExecutionStrategy
    
    /// Maximum orders per day (for dollar cost averaging)
    let maxOrdersPerDay: Int?
    
    /// Whether to use market orders or limit orders
    let useLimitOrders: Bool
    
    /// Limit order buffer (e.g., 0.01 = 1% from current price)
    let limitOrderBuffer: Double?
}

// MARK: - Convenience Extensions

extension RebalancePlan {
    
    /// Buy orders only
    var buyOrders: [RebalanceOrder] {
        orders.filter { $0.action == .buy }
    }
    
    /// Sell orders only
    var sellOrders: [RebalanceOrder] {
        orders.filter { $0.action == .sell }
    }
    
    /// Orders sorted by priority (high to low)
    var prioritizedOrders: [RebalanceOrder] {
        orders.sorted { $0.priority > $1.priority }
    }
    
    /// Total number of orders
    var orderCount: Int {
        orders.count
    }
    
    /// Estimated transaction count (round trip)
    var transactionCount: Int {
        orders.count
    }
    
    /// Formatted summary
    var summary: String {
        var result = "Rebalance Plan: \(portfolioName ?? "Portfolio")\n"
        result += "Status: \(status.displayName)\n"
        result += "Created: \(createdAt.formatted(date: .abbreviated, time: .shortened))\n\n"
        
        result += "Orders (\(orderCount)):\n"
        for order in prioritizedOrders {
            let amount = String(format: "%.2f", order.estimatedAmount)
            result += "- \(order.action.displayName) \(order.shares) \(order.symbol) ($\(amount))\n"
        }
        
        result += "\nTotals:\n"
        result += "- Buy: $\(String(format: "%.2f", totalBuyAmount))\n"
        result += "- Sell: $\(String(format: "%.2f", totalSellAmount))\n"
        result += "- Net Cash: $\(String(format: "%.2f", netCashNeeded))\n"
        
        if let tax = estimatedTaxImpact {
            result += "- Est. Tax Impact: $\(String(format: "%.2f", tax))\n"
        }
        
        return result
    }
    
    /// Checks if plan can be executed with available cash
    /// - Parameter availableCash: Cash available for trading
    /// - Returns: True if sufficient cash
    func canExecute(with availableCash: Double) -> Bool {
        // If net cash needed is negative (selling more than buying), always executable
        guard netCashNeeded > 0 else { return true }
        
        // Need enough cash for net purchases
        return availableCash >= netCashNeeded
    }
    
    /// Creates an executed copy of the plan
    func markAsExecuted() -> RebalancePlan {
        RebalancePlan(
            id: id,
            portfolioId: portfolioId,
            portfolioName: portfolioName,
            createdAt: createdAt,
            status: .executed,
            orders: orders,
            driftAnalysis: driftAnalysis,
            estimatedTaxImpact: estimatedTaxImpact,
            notes: notes
        )
    }
    
    /// Creates a cancelled copy of the plan
    func markAsCancelled(reason: String? = nil) -> RebalancePlan {
        let combinedNotes: String
        if let existingNotes = notes, let reason = reason {
            combinedNotes = "\(existingNotes)\nCancelled: \(reason)"
        } else if let reason = reason {
            combinedNotes = "Cancelled: \(reason)"
        } else {
            combinedNotes = notes ?? ""
        }
        
        return RebalancePlan(
            id: id,
            portfolioId: portfolioId,
            portfolioName: portfolioName,
            createdAt: createdAt,
            status: .cancelled,
            orders: orders,
            driftAnalysis: driftAnalysis,
            estimatedTaxImpact: estimatedTaxImpact,
            notes: combinedNotes
        )
    }
}

extension RebalanceOrder {
    
    /// Formatted string for display
    var displayString: String {
        let amount = String(format: "%.2f", estimatedAmount)
        let shareStr = String(format: "%.0f", shares)
        return "\(action.displayName) \(shareStr) \(symbol) ($\(amount))"
    }
    
    /// Creates a high priority version
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

// MARK: - Validation

struct RebalancePlanValidator {
    
    /// Validates a plan for common issues
    /// - Parameter plan: Plan to validate
    /// - Returns: Array of validation messages (empty if valid)
    static func validate(_ plan: RebalancePlan) -> [String] {
        var issues: [String] = []
        
        // Check for empty plan
        if plan.orders.isEmpty {
            issues.append("Plan has no orders")
        }
        
        // Check for negative shares
        for order in plan.orders where order.shares <= 0 {
            issues.append("\(order.symbol): Invalid share count \(order.shares)")
        }
        
        // Check for zero prices
        for order in plan.orders where order.estimatedPrice <= 0 {
            issues.append("\(order.symbol): Invalid price \(order.estimatedPrice)")
        }
        
        // Check for extreme allocations
        let totalBuyRatio = plan.totalBuyAmount / (plan.totalSellAmount + plan.totalBuyAmount + 1)
        if totalBuyRatio > 0.9 {
            issues.append("Plan is heavily skewed toward buying (\(Int(totalBuyRatio * 100))%)")
        }
        if totalBuyRatio < 0.1 {
            issues.append("Plan is heavily skewed toward selling (\(Int((1-totalBuyRatio) * 100))%)")
        }
        
        return issues
    }
    
    /// Checks if plan is valid
    static func isValid(_ plan: RebalancePlan) -> Bool {
        validate(plan).isEmpty
    }
}
