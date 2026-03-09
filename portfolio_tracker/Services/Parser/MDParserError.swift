//
//  MDParserError.swift
//  portfolio_tracker
//
//  Error types for Markdown parser
//

import Foundation

/// Errors that can occur during Markdown parsing
enum MDParserError: LocalizedError, Sendable {
    case emptyContent
    case missingPortfolioName
    case invalidRiskProfile(String)
    case invalidAssetType(String)
    case invalidMarket(String)
    case invalidRebalancingFrequency(String)
    case invalidNumericValue(field: String, value: String)
    case invalidPercentageValue(field: String, value: String)
    case invalidTableFormat
    case invalidPositionFormat(line: String)
    case missingRequiredField(String)
    case duplicateSymbol(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Markdown content is empty"
        case .missingPortfolioName:
            return "Missing portfolio name (expected '# Portfolio Name')"
        case .invalidRiskProfile(let value):
            return "Invalid risk profile: '\(value)'. Use: conservative, moderate, or aggressive"
        case .invalidAssetType(let value):
            return "Invalid asset type: '\(value)'. Use: stock, fund, etf, bond, or cash"
        case .invalidMarket(let value):
            return "Invalid market: '\(value)'. Use: US, HK, or CN"
        case .invalidRebalancingFrequency(let value):
            return "Invalid rebalancing frequency: '\(value)'. Use: monthly or quarterly"
        case .invalidNumericValue(let field, let value):
            return "Invalid numeric value for '\(field)': '\(value)'"
        case .invalidPercentageValue(let field, let value):
            return "Invalid percentage for '\(field)': '\(value)'. Use decimal (0.08) or percentage (8%)"
        case .invalidTableFormat:
            return "Invalid table format. Expected: | Symbol | Shares | Cost |"
        case .invalidPositionFormat(let line):
            return "Invalid position format: '\(line)'"
        case .missingRequiredField(let field):
            return "Missing required field: '\(field)'"
        case .duplicateSymbol(let symbol):
            return "Duplicate symbol found: '\(symbol)'"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .emptyContent:
            return "Please provide non-empty Markdown content"
        case .missingPortfolioName:
            return "Add a portfolio name at the start: '# My Portfolio'"
        case .invalidRiskProfile:
            return "Valid values: conservative, moderate, aggressive"
        case .invalidAssetType:
            return "Valid values: stock, fund, etf, bond, cash"
        case .invalidMarket:
            return "Valid values: US, HK, CN"
        case .invalidRebalancingFrequency:
            return "Valid values: monthly, quarterly"
        case .invalidNumericValue, .invalidPercentageValue:
            return "Use format: 150.50 or 8%"
        case .invalidTableFormat:
            return "Use markdown table format with | delimiters"
        case .invalidPositionFormat:
            return "Expected format: SYMBOL | Shares | Cost or - SYMBOL: shares @ cost"
        case .missingRequiredField(let field):
            return "Please provide a value for '\(field)'"
        case .duplicateSymbol:
            return "Remove duplicate entries or merge them"
        }
    }
}
