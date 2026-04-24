//
//  KimiService.swift
//  portfolio_tracker
//
//  Kimi API implementation for LLM chat
//

import Foundation
import os.log

/// Kimi API service implementation
///
/// Supports both:
/// - Moonshot AI Platform (platform.moonshot.cn) - API: api.moonshot.cn/v1
/// - Kimi Web Platform (kimi.com) - API: kimi.com/api
///
/// Uses OpenAI-compatible API format
actor KimiService: LLMServiceProtocol {
    
    // MARK: - Properties
    
    private let apiKeyManager: APIKeyManager
    private let configuration: LLMConfiguration
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "KimiService")
    
    /// Whether this service supports web search (native Kimi $web_search)
    nonisolated let supportsWebSearch: Bool = true

    /// Whether this service can autonomously decide when to search
    nonisolated let supportsAutonomousWebSearch: Bool = true
    
    /// API Endpoint options
    enum APIEndpoint: String, Sendable {
        case moonshot = "https://api.moonshot.cn/v1"       // platform.moonshot.cn
        case kimiWeb = "https://kimi.com/api/v1"            // kimi.com web platform  
        case kimiCoding = "https://api.kimi.com/coding/v1"  // kimi.com coding API
        case custom                                    // Custom endpoint (set via init)
    }
    
    /// Custom base URL for custom endpoint
    private let customBaseURL: String?
    
    /// Custom headers to add to requests
    private let customHeaders: [String: String]?
    
    private let endpoint: APIEndpoint
    private var baseURL: String { 
        if endpoint == .custom, let customURL = customBaseURL {
            return customURL
        }
        return endpoint.rawValue 
    }
    
    // MARK: - Initialization
    
    init(
        apiKeyManager: APIKeyManager = .shared,
        configuration: LLMConfiguration = .default,
        urlSession: URLSession? = nil,
        endpoint: APIEndpoint = .kimiCoding,
        customBaseURL: String? = nil,
        customHeaders: [String: String]? = nil
    ) {
        self.apiKeyManager = apiKeyManager
        self.configuration = configuration
        self.endpoint = endpoint
        self.customBaseURL = customBaseURL
        self.customHeaders = customHeaders
        
        // Configure URLSession with timeout
        if let urlSession = urlSession {
            self.urlSession = urlSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = configuration.requestTimeout
            config.timeoutIntervalForResource = configuration.requestTimeout * 2
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
                    guard let apiKey = try? await apiKeyManager.getKey(for: .kimi) else {
                        throw LLMServiceError.apiKeyMissing
                    }

                    // Check if SerpAPI is configured for web search capability
                    let webSearchAvailable = await SerpAPIService.shared.isConfigured()

                    // Use unified message flow - Kimi decides when to use web search
                    try await sendMessageWithOptionalWebSearch(
                        message: message,
                        context: context,
                        history: history,
                        apiKey: apiKey,
                        includeWebSearchTool: webSearchAvailable,
                        continuation: continuation
                    )

                } catch let error as LLMServiceError {
                    logger.error("[Kimi] LLM error: \(error.localizedDescription)")
                    continuation.yield(.failure(error))
                    continuation.finish()
                } catch {
                    logger.error("[Kimi] Unexpected error: \(error.localizedDescription)")
                    continuation.yield(.failure(.networkError(error.localizedDescription)))
                    continuation.finish()
                }
            }

            // Handle cancellation
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Unified message flow with optional web search tool
    /// Kimi autonomously decides when to invoke the web search tool
    private func sendMessageWithOptionalWebSearch(
        message: String,
        context: ConversationContext,
        history: [ChatMessage],
        apiKey: String,
        includeWebSearchTool: Bool,
        continuation: AsyncStream<Result<String, LLMServiceError>>.Continuation
    ) async throws {
        logger.info("Sending message to Kimi API (webSearch available: \(includeWebSearchTool))")

        // Build initial messages
        var messages = buildMessages(message: message, context: context, history: history)

        // Step 1: Send request with tool enabled (if available)
        let requestBody = buildRequestBodyWithTools(messages: messages, enableWebSearch: includeWebSearchTool)
        let request = try buildRequestFromParts(apiKey: apiKey, body: requestBody)

        let (bytes, response) = try await performRequestWithRetry(request: request)
        try validateResponse(response)

        // If web search tool not included, stream normally
        guard includeWebSearchTool else {
            for try await line in bytes.lines {
                if Task.isCancelled { throw LLMServiceError.cancelled }
                if let content = parseSSELine(line) {
                    continuation.yield(.success(content))
                }
            }
            logger.info("Streaming completed (no web search tool)")
            continuation.finish()
            return
        }

        // Handle potential tool calls for web search
        var toolCalls: [[String: Any]] = []
        var accumulatedContent = ""
        var hasToolCalls = false

        // Step 2: Parse initial response stream
        for try await line in bytes.lines {
            if Task.isCancelled { throw LLMServiceError.cancelled }

            let parsed = parseSSELineWithToolCalls(line)

            if let content = parsed.content {
                accumulatedContent += content
                continuation.yield(.success(content))
            }

            if let tc = parsed.toolCalls {
                toolCalls.append(contentsOf: tc)
            }

            if let finishReason = parsed.finishReason, finishReason == "tool_calls" {
                hasToolCalls = true
                break
            }
        }

        // Step 3: If tool calls detected, send tool response and continue
        if hasToolCalls && !toolCalls.isEmpty {
            logger.info("Kimi requested tool calls, sending tool response")

            // Add assistant message with tool calls
            var assistantMessage: [String: Any] = ["role": "assistant"]
            if !accumulatedContent.isEmpty {
                assistantMessage["content"] = accumulatedContent
            }
            assistantMessage["tool_calls"] = toolCalls
            messages.append(assistantMessage)

            // Add tool response for each tool call.
            //
            // For Kimi's `$web_search` builtin the search payload is returned
            // *inside* the tool call itself — the model expects us to echo it
            // back as the `tool` role's content. The exact field has shifted
            // across API versions, so we accept either `function.arguments`
            // (current), `function.result`, or a top-level `result`/`search_result`
            // on the tool call object.
            for toolCall in toolCalls {
                guard let toolCallId = toolCall["id"] as? String else {
                    logger.warning("Kimi tool_call missing 'id'; skipping")
                    continue
                }

                let function = toolCall["function"] as? [String: Any] ?? [:]
                let content: String? = (function["arguments"] as? String)
                    ?? (function["result"] as? String)
                    ?? (toolCall["result"] as? String)
                    ?? (toolCall["search_result"] as? String)

                guard let payload = content, !payload.isEmpty else {
                    let fields = toolCall.keys.sorted().joined(separator: ",")
                    logger.error("Kimi $web_search tool_call has no recognizable payload; fields: \(fields)")
                    continue
                }

                messages.append([
                    "role": "tool",
                    "tool_call_id": toolCallId,
                    "content": payload
                ])
            }

            // Step 4: Continue conversation with tool results
            let followUpBody = buildRequestBody(messages: messages, enableWebSearch: false)
            let followUpRequest = try buildRequestFromParts(apiKey: apiKey, body: followUpBody)

            let (followUpBytes, followUpResponse) = try await performRequestWithRetry(request: followUpRequest)
            try validateResponse(followUpResponse)

            // Stream final response
            for try await followUpLine in followUpBytes.lines {
                if Task.isCancelled { throw LLMServiceError.cancelled }
                if let content = parseSSELine(followUpLine) {
                    continuation.yield(.success(content))
                }
            }
        }

        logger.info("Streaming completed")
        continuation.finish()
    }
    
    func validateAPIKey() async -> APIKeyValidationResult {
        do {
            // Check if API key exists
            guard (try? await apiKeyManager.getKey(for: .kimi)) != nil else {
                return .notConfigured
            }

            // Make a simple test request
            let stream = sendMessage(
                "Hello",
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
            
            var receivedContent = false
            for await result in stream {
                switch result {
                case .success:
                    receivedContent = true
                case .failure(let error):
                    switch error {
                    case .invalidAPIKey:
                        return .invalid
                    case .rateLimited:
                        return .rateLimited
                    case .serviceUnavailable:
                        return .serviceUnavailable
                    case .networkError(let message):
                        return .networkError(message)
                    default:
                        return .networkError(error.localizedDescription)
                    }
                }
                if receivedContent { break }
            }
            
            return receivedContent ? .valid : .invalid
        }
    }
    
    func clearHistory() {
        // KimiService is stateless - history is passed in with each request
        // This method is provided for protocol conformance
    }
    
    // MARK: - Private Methods
    
    /// Performs a request with retry logic for transient failures
    private func performRequestWithRetry(request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var lastError: Error?
        
        for attempt in 0..<configuration.maxRetries {
            do {
                let (bytes, response) = try await urlSession.bytes(for: request)
                return (bytes, response)
            } catch {
                lastError = error
                
                // Check if error is retryable
                if isRetryableError(error) && attempt < configuration.maxRetries - 1 {
                    logger.warning("Request failed (attempt \(attempt + 1)), retrying after delay...")
                    try await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * Double(attempt + 1) * 1_000_000_000))
                } else {
                    break
                }
            }
        }
        
        if let urlError = lastError as? URLError {
            switch urlError.code {
            case .timedOut:
                throw LLMServiceError.requestTimeout
            case .notConnectedToInternet:
                throw LLMServiceError.networkError("No internet connection")
            default:
                throw LLMServiceError.networkError(urlError.localizedDescription)
            }
        }
        
        throw LLMServiceError.maxRetriesExceeded
    }
    
    /// Determines if an error is retryable
    private func isRetryableError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }
    
    private func buildRequest(
        message: String,
        context: ConversationContext,
        history: [ChatMessage],
        apiKey: String,
        enableWebSearch: Bool = false
    ) throws -> URLRequest {
        let messages = buildMessages(message: message, context: context, history: history)
        let requestBody = buildRequestBodyWithTools(messages: messages, enableWebSearch: enableWebSearch)
        return try buildRequestFromParts(apiKey: apiKey, body: requestBody)
    }
    
    private func buildRequestFromParts(apiKey: String, body: [String: Any]) throws -> URLRequest {
        guard let url = buildURL() else {
            throw LLMServiceError.invalidResponse(statusCode: nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        applyAuthentication(to: &request, apiKey: apiKey)
        applyCustomHeaders(to: &request)
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return request
    }
    
    private func buildURL() -> URL? {
        URL(string: "\(baseURL)/chat/completions")
    }
    
    private func buildMessages(
        message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        
        // Add system prompt
        let systemPrompt = SystemPrompts.basePrompt + SystemPrompts.buildContextString(context: context)
        messages.append([
            "role": "system",
            "content": systemPrompt
        ])
        
        // Token-budgeted history (CJK-aware).
        let systemTokens = TokenEstimator.estimate((messages[0]["content"] as? String) ?? "")
        let messageTokens = TokenEstimator.estimate(message)
        // Reserve configuration.maxTokens for the model's reply.
        let budget = max(0, configuration.maxContextLength - systemTokens - messageTokens - configuration.maxTokens)
        let limitedHistory = limitHistory(history, tokenBudget: budget)

        for chatMessage in limitedHistory {
            messages.append([
                "role": chatMessage.role.rawValue,
                "content": chatMessage.content
            ])
        }
        
        // Add user message
        messages.append(["role": "user", "content": message])
        
        return messages
    }
    
    /// Limits history to fit within the given token budget, newest-first.
    /// Caps at the most recent 10 messages regardless of budget to keep
    /// long conversations focused.
    private func limitHistory(_ history: [ChatMessage], tokenBudget: Int) -> [ChatMessage] {
        var result: [ChatMessage] = []
        var used = 0

        for message in history.suffix(10).reversed() {
            let cost = TokenEstimator.estimate(message.content)
            if used + cost > tokenBudget, !result.isEmpty {
                break
            }
            used += cost
            result.insert(message, at: 0)
        }

        return result
    }
    
    private func buildRequestBodyWithTools(messages: [[String: Any]], enableWebSearch: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": resolveModelName(),
            "messages": messages,
            "temperature": configuration.temperature,
            "max_tokens": configuration.maxTokens,
            "top_p": configuration.topP,
            "stream": true
        ]
        
        // Add web search tool if enabled (Kimi native $web_search)
        if enableWebSearch {
            body["tools"] = [
                [
                    "type": "builtin_function",
                    "function": [
                        "name": "$web_search"
                    ]
                ]
            ]
        }
        
        return body
    }
    
    private func buildRequestBody(messages: [[String: Any]], enableWebSearch: Bool) -> [String: Any] {
        buildRequestBodyWithTools(messages: messages, enableWebSearch: enableWebSearch)
    }
    
    private func resolveModelName() -> String {
        switch endpoint {
        case .kimiWeb, .kimiCoding:
            // For Kimi endpoints, use configuration.model or default to kimi-latest
            return configuration.model.hasPrefix("kimi") ? configuration.model : "kimi-latest"
        case .custom, .moonshot:
            return configuration.model
        }
    }
    
    private func applyAuthentication(to request: inout URLRequest, apiKey: String) {
        switch endpoint {
        case .moonshot:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .kimiWeb:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .kimiCoding:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("claude-code/2.0", forHTTPHeaderField: "User-Agent")
            request.setValue("claude-code", forHTTPHeaderField: "X-Client-Name")
        case .custom:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
    }
    
    private func applyCustomHeaders(to request: inout URLRequest) {
        guard let headers = customHeaders else { return }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse(statusCode: nil)
        }
        
        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw LLMServiceError.invalidAPIKey
        case 429:
            throw LLMServiceError.rateLimited
        case 500...599:
            throw LLMServiceError.serviceUnavailable
        default:
            throw LLMServiceError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }
    
    /// Parses Server-Sent Events (SSE) line
    private func parseSSELine(_ line: String) -> String? {
        parseSSELineWithToolCalls(line).content
    }
    
    /// Parses SSE line with tool call support
    private func parseSSELineWithToolCalls(_ line: String) -> (content: String?, toolCalls: [[String: Any]]?, finishReason: String?) {
        // SSE format: data: {...}
        guard line.hasPrefix("data: ") else {
            return (nil, nil, nil)
        }
        
        let jsonString = String(line.dropFirst(6))
        
        // Check for [DONE]
        if jsonString == "[DONE]" {
            return (nil, nil, nil)
        }
        
        // Parse JSON
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return (nil, nil, nil)
        }
        
        let finishReason = firstChoice["finish_reason"] as? String
        var content: String? = nil
        var toolCalls: [[String: Any]]? = nil
        
        if let delta = firstChoice["delta"] as? [String: Any] {
            content = delta["content"] as? String
            
            if let tc = delta["tool_calls"] as? [[String: Any]] {
                toolCalls = tc
            }
        }
        
        return (content, toolCalls, finishReason)
    }
}
