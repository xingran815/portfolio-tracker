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
    ) -> AsyncStream<Result<String, LLMServiceError>> {
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
                        
                        // Parse SSE line
                        if let content = parseSSELine(line) {
                            continuation.yield(.success(content))
                        }
                    }
                    
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
        
        // Add history with character limit
        var totalLength = messages[0]["content"]?.count ?? 0
        let limitedHistory = limitHistory(history, maxLength: configuration.maxContextLength - totalLength)
        
        for chatMessage in limitedHistory {
            let messageContent = chatMessage.content
            totalLength += messageContent.count
            
            messages.append([
                "role": chatMessage.role.rawValue,
                "content": messageContent
            ])
        }
        
        // Add user message
        messages.append(["role": "user", "content": message])
        
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
        // SSE format: data: {...}
        guard line.hasPrefix("data: ") else {
            return nil
        }
        
        let jsonString = String(line.dropFirst(6))
        
        // Check for [DONE]
        if jsonString == "[DONE]" {
            return nil
        }
        
        // Parse JSON
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any] else {
            return nil
        }
        
        // Extract content
        if let content = delta["content"] as? String {
            return content
        }
        
        return nil
    }
}
