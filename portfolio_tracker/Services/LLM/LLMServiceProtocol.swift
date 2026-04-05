//
//  LLMServiceProtocol.swift
//  portfolio_tracker
//
//  Protocol for LLM chat services
//

import Foundation

/// Role in a chat message
enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

/// A single chat message
struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    
    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// Model for conversation context
struct ConversationContext: Sendable {
    let portfolioName: String?
    let positions: [PositionSummary]
    let riskProfile: String?
    let targetAllocation: [String: Double]?
    
    let totalValue: Double?
    let totalCost: Double?
    let totalProfitLoss: Double?
    let profitLossPercentage: Double?
    let portfolioCurrency: String?
    let expectedReturn: Double?
    let maxDrawdown: Double?
    let exchangeRates: [String: Double]?
    
    struct PositionSummary: Sendable {
        let symbol: String
        let name: String
        let shares: Double
        let currentPrice: Double
        let currentValue: Double
        let totalCost: Double
        let profitLoss: Double?
        let profitLossPercentage: Double?
        let weight: Double?
        let assetType: String
        let market: String
        let currency: String
    }
}

/// Validation result for API key checks
enum APIKeyValidationResult: Sendable {
    case valid
    case notConfigured
    case invalid
    case networkError(String)
    case rateLimited
    case serviceUnavailable
    
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

/// Errors that can occur during LLM operations
enum LLMServiceError: LocalizedError, Sendable {
    case apiKeyMissing
    case invalidAPIKey
    case networkError(String)
    case rateLimited
    case invalidResponse(statusCode: Int?)
    case decodingError(String)
    case contextTooLong
    case serviceUnavailable
    case cancelled
    case requestTimeout
    case maxRetriesExceeded
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "API key not configured. Please add your API key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your API key in Settings."
        case .networkError(let message):
            return "Network error: \(message)"
        case .rateLimited:
            return "Rate limit exceeded. Please wait a moment before trying again."
        case .invalidResponse(let statusCode):
            if let code = statusCode {
                return "Invalid response from AI service (HTTP \(code))"
            }
            return "Invalid response from AI service"
        case .decodingError(let message):
            return "Failed to decode AI response: \(message)"
        case .contextTooLong:
            return "Conversation context is too long. Please start a new chat."
        case .serviceUnavailable:
            return "AI service is temporarily unavailable"
        case .cancelled:
            return "Request was cancelled"
        case .requestTimeout:
            return "Request timed out. Please try again."
        case .maxRetriesExceeded:
            return "Failed to complete request after multiple retries. Please try again later."
        }
    }
}

/// Protocol for LLM services
protocol LLMServiceProtocol: Actor {
    /// Sends a message and returns streaming response
    /// - Parameters:
    ///   - message: User's message
    ///   - context: Portfolio context for personalized responses
    ///   - history: Previous conversation history
    /// - Returns: AsyncStream of response chunks
    func sendMessage(
        _ message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> AsyncStream<Result<String, LLMServiceError>>
    
    /// Validates the API key by making a test request
    /// - Returns: Detailed validation result
    func validateAPIKey() async -> APIKeyValidationResult
    
    /// Clears conversation history
    func clearHistory()
}

/// Configuration for LLM requests
struct LLMConfiguration: Sendable {
    let model: String
    let temperature: Double
    let maxTokens: Int
    let topP: Double
    let requestTimeout: TimeInterval
    let maxRetries: Int
    let retryDelay: TimeInterval
    let maxContextLength: Int
    
    static let `default` = LLMConfiguration(
        model: "moonshot-v1-8k",
        temperature: 0.7,
        maxTokens: 2048,
        topP: 0.9,
        requestTimeout: 30.0,
        maxRetries: 3,
        retryDelay: 1.0,
        maxContextLength: 8000
    )
}

// MARK: - System Prompts

enum SystemPrompts {
    /// Cached system prompt base to avoid rebuilding
    static let basePrompt = """
    You are a professional investment advisor specializing in portfolio management and rebalancing strategies.
    
    Your role:
    1. Analyze the user's portfolio and provide actionable advice
    2. Explain rebalancing recommendations clearly
    3. Answer questions about investment strategies
    4. Consider risk tolerance and investment goals
    5. Provide educational context when relevant
    
    Guidelines:
    - Be concise but thorough
    - Use specific numbers and percentages when analyzing
    - Explain the reasoning behind recommendations
    - Consider tax implications when relevant
    - Always maintain a professional, helpful tone
    - If you don't know something, admit it rather than guessing
    """
    
    /// Builds context-specific part of the prompt
    nonisolated static func buildContextString(context: ConversationContext) -> String {
        var contextString = ""
        
        if let name = context.portfolioName {
            contextString += "\n\nPortfolio: \(name)"
        }
        
        if let risk = context.riskProfile {
            contextString += "\nRisk Profile: \(risk)"
        }
        
        if let currency = context.portfolioCurrency {
            contextString += "\nBase Currency: \(currency)"
        }
        
        if let totalValue = context.totalValue,
           let totalCost = context.totalCost,
           let currency = context.portfolioCurrency {
            
            let currencySymbol = Currency(rawValue: currency)?.symbol ?? currency
            
            contextString += "\n\n═══════════════════════════════════════"
            contextString += "\nPORTFOLIO SUMMARY"
            contextString += "\n═══════════════════════════════════════"
            contextString += "\nTotal Value: \(currencySymbol)\(formatNumber(totalValue))"
            contextString += "\nTotal Cost: \(currencySymbol)\(formatNumber(totalCost))"
            
            if let pl = context.totalProfitLoss {
                let plPercent = context.profitLossPercentage ?? 0
                let sign = pl >= 0 ? "+" : ""
                contextString += "\nGain/Loss: \(sign)\(currencySymbol)\(formatNumber(abs(pl))) (\(sign)\(String(format: "%.1f", plPercent * 100))%)"
            }
        }
        
        let securities = context.positions.filter { $0.assetType != "cash" }
        let cashPositions = context.positions.filter { $0.assetType == "cash" }
        
        if !securities.isEmpty {
            contextString += "\n\n═══════════════════════════════════════"
            contextString += "\nSECURITIES"
            contextString += "\n═══════════════════════════════════════"
            
            for pos in securities {
                let currencySymbol = Currency(rawValue: pos.currency)?.symbol ?? pos.currency
                contextString += "\n• \(pos.symbol) (\(pos.name))"
                contextString += "\n  Shares: \(formatNumber(pos.shares))"
                contextString += "\n  Price: \(currencySymbol)\(formatNumber(pos.currentPrice))"
                contextString += "\n  Value: \(currencySymbol)\(formatNumber(pos.currentValue))"
                contextString += "\n  Cost: \(currencySymbol)\(formatNumber(pos.totalCost))"
                
                if let pl = pos.profitLoss, let plPercent = pos.profitLossPercentage {
                    let sign = pl >= 0 ? "+" : ""
                    contextString += "\n  Return: \(sign)\(String(format: "%.1f", plPercent * 100))%"
                }
                
                if let weight = pos.weight {
                    contextString += "\n  Weight: \(String(format: "%.1f", weight * 100))%"
                }
            }
        }
        
        if !cashPositions.isEmpty {
            contextString += "\n\n═══════════════════════════════════════"
            contextString += "\nCASH"
            contextString += "\n═══════════════════════════════════════"
            
            for cash in cashPositions {
                let currencySymbol = Currency(rawValue: cash.currency)?.symbol ?? cash.currency
                contextString += "\n• \(cash.name): \(currencySymbol)\(formatNumber(cash.currentValue))"
                
                if let rates = context.exchangeRates,
                   let baseCurrency = context.portfolioCurrency,
                   cash.currency != baseCurrency,
                   let baseRate = rates[baseCurrency],
                   let currencyRate = rates[cash.currency] {
                    
                    let convertedValue = cash.currentValue * (baseRate / currencyRate)
                    let baseSymbol = Currency(rawValue: baseCurrency)?.symbol ?? baseCurrency
                    contextString += " (\(baseSymbol)\(formatNumber(convertedValue)))"
                }
            }
            
            let totalCash = cashPositions.reduce(0) { $0 + $1.currentValue }
            if let total = context.totalValue, total > 0 {
                let cashPercent = totalCash / total * 100
                contextString += "\n\nCash Total: \(String(format: "%.1f", cashPercent))% of portfolio"
            }
        }
        
        if let targets = context.targetAllocation, !targets.isEmpty {
            contextString += "\n\n═══════════════════════════════════════"
            contextString += "\nTARGET ALLOCATION"
            contextString += "\n═══════════════════════════════════════"
            
            for (symbol, targetPercent) in targets.sorted(by: { $0.key < $1.key }) {
                let actualPercent = context.positions
                    .filter { $0.symbol == symbol }
                    .compactMap { $0.weight }
                    .first ?? 0
                
                let drift = actualPercent - targetPercent
                let driftStr = drift >= 0 ? "+\(String(format: "%.1f", drift * 100))%" : "\(String(format: "%.1f", drift * 100))%"
                let status = abs(drift) > 0.05 ? " ⚠️" : ""
                
                contextString += "\n• \(symbol): Target \(String(format: "%.1f", targetPercent * 100))%, Actual \(String(format: "%.1f", actualPercent * 100))%, Drift \(driftStr)\(status)"
            }
        }
        
        if let expected = context.expectedReturn, let maxDD = context.maxDrawdown {
            contextString += "\n\n═══════════════════════════════════════"
            contextString += "\nRISK METRICS"
            contextString += "\n═══════════════════════════════════════"
            contextString += "\nExpected Return: \(String(format: "%.1f", expected * 100))%"
            contextString += "\nMax Drawdown Limit: \(String(format: "%.1f", maxDD * 100))%"
        }
        
        return contextString
    }
    
    private static func formatNumber(_ value: Double) -> String {
        if abs(value) >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if abs(value) >= 1_000 {
            return String(format: "%.2fK", value / 1_000)
        } else {
            return String(format: "%.2f", value)
        }
    }
}


