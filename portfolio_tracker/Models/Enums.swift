//
//  Enums.swift
//  portfolio_tracker
//
//  PortfolioTracker enums
//

import Foundation

/// Risk tolerance level for portfolio
public enum RiskProfile: String, CaseIterable, Codable, Sendable {
    case conservative
    case moderate
    case aggressive
    
    public var displayName: String {
        switch self {
        case .conservative: return "保守型"
        case .moderate: return "稳健型"
        case .aggressive: return "激进型"
        }
    }
}

/// Type of financial asset
public enum AssetType: String, CaseIterable, Codable, Sendable {
    case stock
    case fund
    case etf
    case bond
    case cash
    
    public var displayName: String {
        switch self {
        case .stock: return "股票"
        case .fund: return "基金"
        case .etf: return "ETF"
        case .bond: return "债券"
        case .cash: return "现金"
        }
    }
}

/// Market identifier
public enum Market: String, CaseIterable, Codable, Sendable {
    case us = "US"
    case hk = "HK"
    case cn = "CN"
    
    public var displayName: String {
        switch self {
        case .us: return "美股"
        case .hk: return "港股"
        case .cn: return "A股"
        }
    }
    
    public var currency: String {
        switch self {
        case .us: return "USD"
        case .hk: return "HKD"
        case .cn: return "CNY"
        }
    }
}

/// Transaction type
public enum TransactionType: String, CaseIterable, Codable, Sendable {
    case buy
    case sell
    case dividend
    
    public var displayName: String {
        switch self {
        case .buy: return "买入"
        case .sell: return "卖出"
        case .dividend: return "分红"
        }
    }
}

/// Rebalancing frequency
public enum RebalancingFrequency: String, CaseIterable, Codable, Sendable {
    case monthly
    case quarterly
    
    public var displayName: String {
        switch self {
        case .monthly: return "每月"
        case .quarterly: return "每季度"
        }
    }
}

/// Plan status for rebalancing
public enum PlanStatus: String, CaseIterable, Codable, Sendable {
    case draft
    case executed
    case cancelled
    
    public var displayName: String {
        switch self {
        case .draft: return "草稿"
        case .executed: return "已执行"
        case .cancelled: return "已取消"
        }
    }
}
