//
//  BaiduQianfanService.swift
//  portfolio_tracker
//
//  Baidu Qianfan API implementation for LLM chat
//

import Foundation
import os.log

/// Baidu Qianfan API service implementation
///
/// Supports models:
/// - kimi-k2.5 (256k context, 65k output)
/// - glm-5 (198k context, 131k output)
/// - minimax-m2.5 (192k context, 131k output)
///
/// Uses OpenAI-compatible API format with automatic thinking mode
actor BaiduQianfanService: LLMServiceProtocol {
    
    // MARK: - Properties
    
    private let apiKeyManager: APIKeyManager
    private let configuration: LLMConfiguration
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "BaiduQianfanService")
    private let webSearchService = SerpAPIService.shared
    
    /// Base URL for Baidu Qianfan API
    private let baseURL = "https://qianfan.baidubce.com/v2/coding"
    
    /// Whether this service supports web search (via SerpAPI)
    nonisolated let supportsWebSearch: Bool = true

    /// Whether this service can autonomously decide when to search
    nonisolated let supportsAutonomousWebSearch: Bool = true
    
    /// Available models
    enum Model: String, Sendable, CaseIterable {
        case kimi_k2_5 = "kimi-k2.5"
        case glm5 = "glm-5"
        case minimax_m2_5 = "minimax-m2.5"
        
        var displayName: String {
            switch self {
            case .kimi_k2_5: return "Kimi-K2.5 (256k context)"
            case .glm5: return "GLM-5 (198k context)"
            case .minimax_m2_5: return "MiniMax-M2.5 (192k context)"
            }
        }
        
        var contextLimit: Int {
            switch self {
            case .kimi_k2_5: return 256_000
            case .glm5: return 198_000
            case .minimax_m2_5: return 192_000
            }
        }
        
        var outputLimit: Int {
            switch self {
            case .kimi_k2_5: return 65_536
            case .glm5: return 131_072
            case .minimax_m2_5: return 131_072
            }
        }
    }
    
    private let model: Model

    /// Per-session SerpAPI result cache keyed by normalized query.
    /// Prevents repeated calls for the same topic within one conversation.
    private var searchCache: [String: SerpSearchResult] = [:]

    // MARK: - Initialization
    
    init(
        apiKeyManager: APIKeyManager = .shared,
        configuration: LLMConfiguration? = nil,
        urlSession: URLSession? = nil,
        model: Model = .kimi_k2_5
    ) {
        self.apiKeyManager = apiKeyManager
        self.model = model
        
        // Create model-specific default configuration
        let defaultConfig = LLMConfiguration(
            model: model.rawValue,
            temperature: 0.7,
            maxTokens: model.outputLimit,
            topP: 0.9,
            requestTimeout: 90.0,  // 90 seconds for large context models
            maxRetries: 3,
            retryDelay: 1.0,
            maxContextLength: model.contextLimit
        )
        
        self.configuration = configuration ?? defaultConfig
        
        // Configure URLSession with timeout
        if let urlSession = urlSession {
            self.urlSession = urlSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = self.configuration.requestTimeout
            config.timeoutIntervalForResource = self.configuration.requestTimeout * 2
            self.urlSession = URLSession(configuration: config)
        }
    }
    
    // MARK: - LLMServiceProtocol

    func sendMessage(
        _ message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> AsyncStream<Result<String, LLMServiceError>> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    // Get API key
                    guard let apiKey = try? await apiKeyManager.getKey(for: .baiduqianfan) else {
                        throw LLMServiceError.apiKeyMissing
                    }

                    // Check if SerpAPI is configured for web search
                    let serpAPIConfigured = await webSearchService.isConfigured()

                    // Autonomously decide if web search is needed
                    var webSearchContext: String? = nil
                    var searchFailureNote: String? = nil
                    if serpAPIConfigured && needsWebSearch(for: message) {
                        let searchQuery = extractSearchQuery(from: message)
                        let cacheKey = normalizeQueryForCache(searchQuery)
                        if let cached = searchCache[cacheKey] {
                            webSearchContext = cached.toSystemPromptContext()
                            logger.info("Web search cache hit for query '\(searchQuery)'")
                        } else {
                            do {
                                let searchResult = try await webSearchService.search(query: searchQuery)
                                searchCache[cacheKey] = searchResult
                                webSearchContext = searchResult.toSystemPromptContext()
                                logger.info("Autonomous web search triggered with \(searchResult.results.count) results")
                            } catch {
                                logger.warning("Web search failed: \(error.localizedDescription)")
                                searchFailureNote = "网络搜索失败，未能获取最新数据 (Web search failed — no real-time data available)"
                            }
                        }
                    }

                    // Build request
                    let request = try buildRequest(
                        message: message,
                        context: context,
                        history: history,
                        apiKey: apiKey,
                        webSearchContext: webSearchContext,
                        searchFailureNote: searchFailureNote
                    )

                    logger.info("Sending message to Baidu Qianfan API (model: \(self.model.rawValue), webSearch: \(webSearchContext != nil))")
                    
                    // Perform request with retry logic
                    let (bytes, response) = try await performRequestWithRetry(request: request)
                    
                    // Check HTTP response
                    try validateResponse(response)
                    
                    // Parse SSE stream
                    for try await line in bytes.lines {
                        // Check for cancellation
                        if Task.isCancelled {
                            throw LLMServiceError.cancelled
                        }
                        
                        // Parse SSE line (returns content, ignores reasoning)
                        if let content = parseSSELine(line) {
                            continuation.yield(.success(content))
                        }
                    }
                    
                    logger.info("Streaming completed")
                    continuation.finish()
                    
                } catch let error as LLMServiceError {
                    logger.error("[Baidu Qianfan] LLM error: \(error.localizedDescription)")
                    continuation.yield(.failure(error))
                    continuation.finish()
                } catch {
                    logger.error("[Baidu Qianfan] Unexpected error: \(error.localizedDescription)")
                    let wrappedError = LLMServiceError.networkError(error.localizedDescription)
                    continuation.yield(.failure(wrappedError))
                    continuation.finish()
                }
            }
            
            // Handle cancellation
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    func validateAPIKey() async -> APIKeyValidationResult {
        // Check if API key exists
        guard (try? await apiKeyManager.getKey(for: .baiduqianfan)) != nil else {
            return .notConfigured
        }

        // Make a simple test request
        let stream = sendMessage(
            "test",
            context: ConversationContext(
                portfolioName: nil,
                positions: [],
                riskProfile: nil,
                targetAllocation: nil,
                totalValue: nil,
                totalCost: nil,
                totalProfitLoss: nil,
                profitLossPercentage: nil,
                portfolioCurrency: nil,
                expectedReturn: nil,
                maxDrawdown: nil,
                exchangeRates: nil
            ),
            history: []
        )
        
        var hasValidResponse = false
        for await result in stream {
            switch result {
            case .success:
                hasValidResponse = true
                break
            case .failure(let error):
                if case .invalidAPIKey = error {
                    return .invalid
                }
            }
        }
        
        return hasValidResponse ? .valid : .invalid
    }
    
    func clearHistory() {
        searchCache.removeAll()
    }
    
    // MARK: - Request Building
    
    private func buildRequest(
        message: String,
        context: ConversationContext,
        history: [ChatMessage],
        apiKey: String,
        webSearchContext: String? = nil,
        searchFailureNote: String? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMServiceError.networkError("Invalid API URL: \(baseURL)/chat/completions")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": buildMessages(
                message: message,
                context: context,
                history: history,
                webSearchContext: webSearchContext,
                searchFailureNote: searchFailureNote
            ),
            "temperature": configuration.temperature,
            "max_tokens": configuration.maxTokens,
            "stream": true
        ]
        
        // Note: Thinking mode is automatic for Baidu Qianfan models
        // Uses platform default settings (models handle thinking internally)
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    private func buildMessages(
        message: String,
        context: ConversationContext,
        history: [ChatMessage],
        webSearchContext: String? = nil,
        searchFailureNote: String? = nil
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        // System message
        var systemContent = SystemPrompts.basePrompt + SystemPrompts.buildContextString(context: context)

        // Add web search context if available
        if let webContext = webSearchContext {
            systemContent += webContext
        }

        // Surface search failure so the LLM can caveat instead of silently
        // falling back to possibly-stale training data.
        if let note = searchFailureNote {
            systemContent += "\n\n[系统提示 / SYSTEM] \(note)"
        }

        messages.append(["role": "system", "content": systemContent])
        
        // Calculate available tokens for history
        // Reserve tokens for: system message + new message + response buffer
        let systemTokens = estimateTokenCount(systemContent)
        let messageTokens = estimateTokenCount(message)
        let responseBuffer = 4000  // Reserve 4k for response
        let maxHistoryTokens = configuration.maxContextLength - systemTokens - messageTokens - responseBuffer
        
        // Add history messages that fit within token budget (newest first)
        var currentHistoryTokens = 0
        let reversedHistory = history.reversed()
        var includedHistory: [ChatMessage] = []
        
        for msg in reversedHistory {
            let msgTokens = estimateTokenCount(msg.content)
            if currentHistoryTokens + msgTokens > maxHistoryTokens && !includedHistory.isEmpty {
                break  // Stop if we'd exceed budget (but keep at least one message)
            }
            currentHistoryTokens += msgTokens
            includedHistory.insert(msg, at: 0)  // Maintain chronological order
        }
        
        for msg in includedHistory {
            messages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        
        // Current message
        messages.append(["role": "user", "content": message])
        
        return messages
    }
    
    /// Estimates token count for text. Delegates to the shared CJK-aware estimator.
    private func estimateTokenCount(_ text: String) -> Int {
        TokenEstimator.estimate(text)
    }

    /// Normalizes a query for cache lookup: lowercased, trimmed, whitespace-collapsed.
    private func normalizeQueryForCache(_ query: String) -> String {
        query
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    /// Extracts optimal search query from user message
    private func extractSearchQuery(from message: String) -> String {
        // Use short messages as-is
        if message.count < 100 {
            return message
        }
        
        // Keywords indicating financial/investment queries
        let financialKeywords = [
            "股价", "股票", "基金", "市场", "A股", "港股", "美股", "股价",
            "stock", "price", "market", "fund", "index", "ETF",
            "利率", "通胀", "GDP", "美联储", "央行", "降息", "加息",
            "interest rate", "inflation", "Fed", "central bank",
            "财报", "盈利", "营收", "earnings", "revenue",
            "走势", "行情", "趋势", "trend", "forecast"
        ]
        
        // Split into sentences
        let sentences = message.components(separatedBy: CharacterSet(charactersIn: "。！？.!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Score each sentence by keyword matches
        var bestSentence = String(message.prefix(100))
        var bestScore = 0
        
        for sentence in sentences {
            let lowercased = sentence.lowercased()
            let score = financialKeywords.reduce(0) { count, keyword in
                count + (lowercased.contains(keyword.lowercased()) ? 1 : 0)
            }
            
            if score > bestScore {
                bestScore = score
                bestSentence = sentence
            }
        }
        
        logger.debug("Extracted search query: '\(bestSentence)' (score: \(bestScore))")
        return bestSentence
    }

    /// Determines if web search is needed based on message content.
    ///
    /// A search is triggered only when the message contains BOTH:
    ///   1. a topic keyword (stock, fund, market, rates, earnings…), and
    ///   2. a time-sensitivity signal (today, latest, current year, etc.), or
    ///      an explicitly time-sensitive standalone keyword (news, announcement).
    ///
    /// This prevents triggering on generic portfolio discussion like
    /// "讨论一下我的股票组合" — which mentions stocks but does not ask for
    /// real-time data.
    func needsWebSearch(for message: String) -> Bool {
        let lowercased = message.lowercased()

        let topicKeywords = [
            // Chinese topics
            "股价", "股票", "基金", "板块", "行业", "行情", "走势", "涨跌",
            "财报", "盈利", "营收", "业绩", "a股", "港股", "美股", "基金净值",
            "利率", "美联储", "央行", "通胀", "gdp",
            // English topics
            "price", "stock", "fund", "etf", "sector", "industry", "market",
            "trend", "earnings", "revenue", "quarterly", "fed", "interest rate",
            "central bank", "inflation", "gdp"
        ]

        let timeSignals = [
            // Chinese time signals
            "最新", "当前", "今天", "今日", "最近", "现在", "目前", "本周", "本月",
            "今年", "刚刚", "昨天",
            // English time signals
            "latest", "current", "today", "now", "recent", "this week",
            "this month", "this year", "right now",
            // Year tokens — explicit recency
            "2024", "2025", "2026"
        ]

        // Always-time-sensitive standalone keywords. These imply either
        // "as of now", a discrete recent event, or an explicit request
        // from the user to go look something up.
        let standaloneTimeSensitive = [
            // Chinese — event / news
            "新闻", "公告", "加息", "降息", "降准",
            // Chinese — explicit search imperatives
            "查一查", "查一下", "查查", "搜一搜", "搜一下", "搜索",
            // English — event / news
            "news", "announcement", "announce", "breaking",
            // English — explicit search imperatives
            "search", "look up", "google", "find out"
        ]

        for keyword in standaloneTimeSensitive where lowercased.contains(keyword) {
            logger.debug("Web search needed: standalone time-sensitive keyword '\(keyword)'")
            return true
        }

        let hasTopic = topicKeywords.contains { lowercased.contains($0) }
        guard hasTopic else { return false }

        let hasTimeSignal = timeSignals.contains { lowercased.contains($0) }
        if hasTimeSignal {
            logger.debug("Web search needed: topic + time signal detected")
            return true
        }

        return false
    }

    // MARK: - SSE Parsing
    
    private func parseSSELine(_ line: String) -> String? {
        // SSE format: "data: {json}"
        guard line.hasPrefix("data: ") else { return nil }
        
        let jsonStr = String(line.dropFirst(6))
        guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { return nil }
        
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any] else {
            return nil
        }
        
        // Return content if available (ignore reasoning_content for now)
        if let content = delta["content"] as? String {
            return content
        }
        
        return nil
    }
    
    // MARK: - Request Execution
    
    private func performRequestWithRetry(request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var lastError: Error?
        
        for attempt in 0..<configuration.maxRetries {
            do {
                let (bytes, response) = try await urlSession.bytes(for: request)
                
                // Validate response
                try validateResponse(response)
                
                return (bytes, response)
                
            } catch {
                lastError = error
                
                // Check if we should retry
                if isRetryableError(error) && attempt < self.configuration.maxRetries - 1 {
                    let delay = self.configuration.retryDelay * Double(attempt + 1)
                    logger.warning("Request failed, retrying in \(delay)s (attempt \(attempt + 1)/\(self.configuration.maxRetries))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw error
                }
            }
        }
        
        throw lastError ?? LLMServiceError.maxRetriesExceeded
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse(statusCode: nil)
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw LLMServiceError.invalidAPIKey
        case 429:
            throw LLMServiceError.rateLimited
        case 503:
            throw LLMServiceError.serviceUnavailable
        default:
            throw LLMServiceError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }
    
    private func isRetryableError(_ error: Error) -> Bool {
        if let llmError = error as? LLMServiceError {
            switch llmError {
            case .rateLimited, .serviceUnavailable, .networkError:
                return true
            default:
                return false
            }
        }
        return true
    }
}
