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
    /// Non-fatal warnings produced while assembling this context
    /// (e.g. "exchange rate fetch failed") — surfaced to the LLM so it can caveat.
    let contextWarnings: [String]?

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

    init(
        portfolioName: String?,
        positions: [PositionSummary],
        riskProfile: String?,
        targetAllocation: [String: Double]?,
        totalValue: Double?,
        totalCost: Double?,
        totalProfitLoss: Double?,
        profitLossPercentage: Double?,
        portfolioCurrency: String?,
        expectedReturn: Double?,
        maxDrawdown: Double?,
        exchangeRates: [String: Double]?,
        contextWarnings: [String]? = nil
    ) {
        self.portfolioName = portfolioName
        self.positions = positions
        self.riskProfile = riskProfile
        self.targetAllocation = targetAllocation
        self.totalValue = totalValue
        self.totalCost = totalCost
        self.totalProfitLoss = totalProfitLoss
        self.profitLossPercentage = profitLossPercentage
        self.portfolioCurrency = portfolioCurrency
        self.expectedReturn = expectedReturn
        self.maxDrawdown = maxDrawdown
        self.exchangeRates = exchangeRates
        self.contextWarnings = contextWarnings
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
            return "API 密钥未配置，请在设置中添加 (API key not configured)"
        case .invalidAPIKey:
            return "API 密钥无效，请在设置中检查 (Invalid API key)"
        case .networkError(let message):
            return "网络错误 (Network error): \(message)"
        case .rateLimited:
            return "请求过于频繁，请稍后再试 (Rate limit exceeded)"
        case .invalidResponse(let statusCode):
            if let code = statusCode {
                return "AI 服务响应异常 (Invalid response, HTTP \(code))"
            }
            return "AI 服务响应异常 (Invalid response)"
        case .decodingError(let message):
            return "解析 AI 响应失败 (Failed to decode response): \(message)"
        case .contextTooLong:
            return "对话上下文过长，请开启新对话 (Context too long — start a new chat)"
        case .serviceUnavailable:
            return "AI 服务暂时不可用 (Service temporarily unavailable)"
        case .cancelled:
            return "请求已取消 (Request cancelled)"
        case .requestTimeout:
            return "请求超时，请重试 (Request timed out)"
        case .maxRetriesExceeded:
            return "多次重试后仍然失败，请稍后再试 (Max retries exceeded)"
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

    /// Whether this service supports web search
    var supportsWebSearch: Bool { get }

    /// Whether this service can autonomously decide when to search
    var supportsAutonomousWebSearch: Bool { get }
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
        maxTokens: 4096,
        topP: 0.9,
        requestTimeout: 30.0,
        maxRetries: 3,
        retryDelay: 1.0,
        maxContextLength: 8000
    )
}

// MARK: - Token Estimation

/// Shared token estimator used by both LLM services to budget context.
///
/// ASCII-heavy text averages ~4 chars/token; Chinese (CJK Unified Ideographs)
/// averages ~1.5 chars/token. Mixed text is handled by bucketing each scalar.
enum TokenEstimator {
    nonisolated static func estimate(_ text: String) -> Int {
        var asciiCount = 0
        var cjkCount = 0
        var otherCount = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v < 0x80 {
                asciiCount += 1
            } else if (0x4E00...0x9FFF).contains(v) ||
                      (0x3000...0x30FF).contains(v) ||
                      (0xAC00...0xD7AF).contains(v) {
                cjkCount += 1
            } else {
                otherCount += 1
            }
        }
        let approx = Double(asciiCount) / 4.0
            + Double(cjkCount) / 1.5
            + Double(otherCount) / 2.5
        return max(1, Int(approx.rounded(.up)))
    }
}

// MARK: - System Prompts

enum SystemPrompts {
    /// System prompt base with current date and web search instructions
    static let basePrompt: String = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        let currentDate = dateFormatter.string(from: Date())
        
        return """
        You are a professional investment advisor specializing in portfolio management and rebalancing strategies.

        **CURRENT DATE: \(currentDate)**

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

        **LANGUAGE:**
        - Respond in the language of the user's most recent message. If the user writes in Chinese, respond in Chinese; if English, respond in English. Keep numbers, tickers, and proper nouns untranslated.

        **PORTFOLIO CONTEXT FORMAT (below, if present):**
        - Data is split into sections delimited by lines of `═══` with an ALL-CAPS section title.
        - Percentages shown as `12.3%` are already multiplied by 100 (human-readable). Underlying weights in `TARGET ALLOCATION` are derived from decimals (0.05 means 5%).
        - Currency amounts are prefixed with a currency symbol or ISO code. Values shown as `1.23K` / `4.56M` are thousands / millions.
        - A `Drift` value is `actual − target`; negative means the position is under-weight vs. target.
        - If a `SYSTEM WARNINGS` section is present, some data may be stale or missing — caveat your answer accordingly and do not invent values to fill the gap.

        **WEB SEARCH RESULTS HANDLING:**
        When web search results are provided in the conversation context:
        - You MUST use the information from web search results to answer questions
        - Web search results contain REAL-TIME data as of the current date shown above
        - This information supersedes your training knowledge which may be outdated
        - ALWAYS cite sources using [1], [2], [3] format when referencing search data
        - NEVER say you cannot access current information when web search results are provided
        - If the user asks about recent market data, prices, or news, rely on web search results
        """
    }()
    
    /// Builds context-specific part of the prompt
    nonisolated static func buildContextString(context: ConversationContext) -> String {
        var contextString = ""

        if let warnings = context.contextWarnings, !warnings.isEmpty {
            contextString += "\n\n═══════════════════════════════════════"
            contextString += "\nSYSTEM WARNINGS"
            contextString += "\n═══════════════════════════════════════"
            for warning in warnings {
                contextString += "\n• \(warning)"
            }
        }

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
                let status = abs(drift) > 0.01 ? " [DRIFT]" : ""

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


