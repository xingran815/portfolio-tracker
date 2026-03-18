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
    ) -> AsyncStream<Result<StreamChunk, LLMServiceError>> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    // Get API key
                    guard let apiKey = try? await apiKeyManager.getKey(for: .kimi) else {
                        throw LLMServiceError.apiKeyMissing
                    }
                    
                    // Build request
                    let request = try buildRequest(
                        message: message,
                        context: context,
                        history: history,
                        apiKey: apiKey
                    )
                    
                    logger.info("Sending message to Kimi API")
                    
                    // Debug: Log request details
                    if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
                        logger.debug("Request body: \(bodyString)")
                    }
                    logger.debug("Request headers: \(request.allHTTPHeaderFields ?? [:])")
                    
                    // Perform request with retry logic
                    let (bytes, response) = try await performRequestWithRetry(request: request)
                    
                    // Check HTTP response
                    try validateResponse(response)
                    
                    // Parse SSE stream
                    var totalChunks = 0
                    var contentChunks = 0
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            throw LLMServiceError.cancelled
                        }
                        
                        totalChunks += 1
                        logger.debug("SSE Line #\(totalChunks): \(line)")
                        
                        if let chunk = parseSSELine(line) {
                            contentChunks += 1
                            logger.debug("Extracted chunk #\(contentChunks): \(chunk.content.prefix(50))")
                            continuation.yield(.success(chunk))
                        }
                    }
                    logger.info("Stream ended: \(totalChunks) total chunks, \(contentChunks) content chunks")
                    
                    logger.info("Streaming completed")
                    continuation.finish()
                    
                } catch let error as LLMServiceError {
                    logger.error("LLM error: \(error.localizedDescription)")
                    continuation.yield(.failure(error))
                    continuation.finish()
                } catch {
                    logger.error("Unexpected error: \(error.localizedDescription)")
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
                    targetAllocation: nil
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
        apiKey: String
    ) throws -> URLRequest {
        guard let url = buildURL() else {
            throw LLMServiceError.invalidResponse(statusCode: nil)
        }
        
        let messages = buildMessages(message: message, context: context, history: history)
        let requestBody = buildRequestBody(messages: messages)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        applyAuthentication(to: &request, apiKey: apiKey)
        applyCustomHeaders(to: &request)
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
    
    private func buildURL() -> URL? {
        URL(string: "\(baseURL)/chat/completions")
    }
    
    private func buildMessages(
        message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> [[String: String]] {
        var messages: [[String: String]] = []
        
        // Add system prompt
        let systemPrompt = SystemPrompts.basePrompt + SystemPrompts.buildContextString(context: context)
        messages.append([
            "role": "system",
            "content": systemPrompt
        ])
        
        // Filter out empty messages and deduplicate consecutive messages from same role
        var seenContent = Set<String>()
        var lastRole: String?
        
        for chatMessage in history {
            // Skip empty messages
            guard !chatMessage.content.isEmpty else { continue }
            
            // Skip duplicates (same content)
            let contentKey = "\(chatMessage.role.rawValue):\(chatMessage.content)"
            guard !seenContent.contains(contentKey) else { continue }
            seenContent.insert(contentKey)
            
            // Skip consecutive messages from same role (API requires alternating user/assistant)
            let currentRole = chatMessage.role.rawValue
            guard currentRole != lastRole else { continue }
            lastRole = currentRole
            
            messages.append([
                "role": currentRole,
                "content": chatMessage.content
            ])
        }
        
        // Ensure we don't end with an assistant message (should alternate ending with user)
        if messages.last?["role"] == "assistant" {
            messages.removeLast()
        }
        
        // Add current user message
        messages.append(["role": "user", "content": message])
        
        // Limit total messages to avoid token limits
        if messages.count > 20 {
            // Keep system message and last 19 messages
            let systemMessage = messages[0]
            messages = [systemMessage] + messages.suffix(19)
        }
        
        return messages
    }
    
    /// Limits history to fit within context length
    private func limitHistory(_ history: [ChatMessage], maxLength: Int) -> [ChatMessage] {
        var result: [ChatMessage] = []
        var currentLength = 0
        
        // Iterate from most recent, keeping messages that fit
        for message in history.suffix(10).reversed() {
            let messageLength = message.content.count
            if currentLength + messageLength > maxLength {
                break
            }
            currentLength += messageLength
            result.insert(message, at: 0)
        }
        
        return result
    }
    
    private func buildRequestBody(messages: [[String: String]]) -> [String: Any] {
        [
            "model": resolveModelName(),
            "messages": messages,
            "temperature": configuration.temperature,
            "max_tokens": configuration.maxTokens,
            "top_p": configuration.topP,
            "stream": true
        ]
    }
    
    private func resolveModelName() -> String {
        // Always use the configured model name as-is
        return configuration.model
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
            request.setValue("claude-code/1.0", forHTTPHeaderField: "User-Agent")
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
        
        logger.debug("HTTP Response status: \(httpResponse.statusCode)")
        logger.debug("HTTP Response headers: \(httpResponse.allHeaderFields)")
        
        switch httpResponse.statusCode {
        case 200:
            return
        case 400:
            logger.error("HTTP 400 Bad Request - Invalid request format")
            throw LLMServiceError.invalidResponse(statusCode: 400)
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
    private func parseSSELine(_ line: String) -> StreamChunk? {
        guard line.hasPrefix("data:") else {
            return nil
        }
        
        var jsonString = String(line.dropFirst(5))
        if jsonString.hasPrefix(" ") {
            jsonString = String(jsonString.dropFirst())
        }
        
        if jsonString == "[DONE]" {
            return nil
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            logger.error("Failed to convert SSE data to UTF-8")
            return nil
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Failed to parse JSON: \(jsonString.prefix(200))")
            return nil
        }
        
        logger.debug("JSON top-level keys: \(json.keys)")
        
        guard let choices = json["choices"] as? [[String: Any]] else {
            logger.error("No 'choices' array in JSON. Keys: \(json.keys)")
            return nil
        }
        
        guard let firstChoice = choices.first else {
            logger.error("Empty choices array")
            return nil
        }
        
        guard let delta = firstChoice["delta"] as? [String: Any] else {
            logger.error("No 'delta' in first choice. Keys: \(firstChoice.keys)")
            return nil
        }
        
        logger.debug("SSE delta keys: \(delta.keys)")
        
        // Check for content (final answer) - preferred
        if let content = delta["content"] as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                logger.debug("Found content field: '\(content.prefix(50))' (length: \(content.count))")
                return StreamChunk(content: content, type: .content)
            }
        }
        
        // Fall back to reasoning_content (thinking process)
        if let reasoningContent = delta["reasoning_content"] as? String {
            let trimmed = reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                logger.debug("Found reasoning_content field: '\(reasoningContent.prefix(50))' (length: \(reasoningContent.count))")
                return StreamChunk(content: reasoningContent, type: .reasoning)
            }
        }
        
        logger.debug("No content or reasoning_content found in delta")
        return nil
    }
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
    
    General Rules:
    - Always respond in the same language as the user's query (English or Chinese)
    - Prioritize user safety and ethical investment practices
    - Do not provide specific buy/sell recommendations for individual securities
    - Focus on portfolio-level analysis and asset allocation strategies
    - When discussing risks, be balanced and mention both upside and downside potential
    - Use clear, jargon-free language unless explaining technical terms
    - Format numerical data clearly with appropriate units (%, $, etc.)
    - If portfolio data is incomplete, ask clarifying questions
    - Respect user privacy - do not ask for personal financial details beyond portfolio composition
    - Stay within scope: investment advice only, no unrelated topics
    - When uncertain, recommend consulting a qualified financial advisor
    """
    
    
    /// Builds context-specific part of the prompt
    static func buildContextString(context: ConversationContext) -> String {
        var contextString = ""
        
        // Add portfolio context if available
        if let portfolioName = context.portfolioName {
            contextString += "\n\nPortfolio: \(portfolioName)"
        }
        
        if let riskProfile = context.riskProfile {
            contextString += "\nRisk Profile: \(riskProfile)"
        }
        
        if !context.positions.isEmpty {
            contextString += "\n\nCurrent Positions:"
            for position in context.positions {
                contextString += "\n- \(position.symbol): \(String(format: "%.2f", position.shares)) shares"
            }
        }
        
        if let allocation = context.targetAllocation, !allocation.isEmpty {
            contextString += "\n\nTarget Allocation:"
            for (symbol, percentage) in allocation {
                contextString += "\n- \(symbol): \(String(format: "%.1f", percentage * 100))%"
            }
        }
        
        contextString += "\n\nRemember: This is educational advice. Always consult with a licensed financial advisor for personalized recommendations."
        
        return contextString
    }
}
