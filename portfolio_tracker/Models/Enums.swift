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

/// Currency for portfolio display
public enum Currency: String, CaseIterable, Codable, Sendable {
    case cny = "CNY"
    case usd = "USD"
    case eur = "EUR"
    case hkd = "HKD"
    case gbp = "GBP"
    case jpy = "JPY"
    
    public var displayName: String {
        switch self {
        case .cny: return "人民币 (¥)"
        case .usd: return "美元 ($)"
        case .eur: return "欧元 (€)"
        case .hkd: return "港币 (HK$)"
        case .gbp: return "英镑 (£)"
        case .jpy: return "日元 (¥)"
        }
    }
    
    public var symbol: String {
        switch self {
        case .cny: return "¥"
        case .usd: return "$"
        case .eur: return "€"
        case .hkd: return "HK$"
        case .gbp: return "£"
        case .jpy: return "¥"
        }
    }
    
    public var code: String {
        return self.rawValue
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
    // swiftlint:disable identifier_name
    case us = "US"
    case hk = "HK"
    case cn = "CN"
    // swiftlint:enable identifier_name
    
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
    
    public var currencySymbol: String {
        switch self {
        case .us: return "$"
        case .hk: return "HK$"
        case .cn: return "¥"
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

/// Position management errors
public enum PositionError: LocalizedError, Sendable {
    case insufficientShares(available: Double, requested: Double)
    case positionNotFound
    case invalidInput(String)
    
    public var errorDescription: String? {
        switch self {
        case .insufficientShares(let available, let requested):
            return "持仓不足：可用 \(String(format: "%.2f", available)) 股，请求卖出 \(String(format: "%.2f", requested)) 股"
        case .positionNotFound:
            return "未找到该持仓"
        case .invalidInput(let message):
            return "输入无效：\(message)"
        }
    }
}
