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
    
    /// Base URL for Baidu Qianfan API
    private let baseURL = "https://qianfan.baidubce.com/v2/coding"
    
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
    }
    
    private let model: Model
    
    // MARK: - Initialization
    
    init(
        apiKeyManager: APIKeyManager = .shared,
        configuration: LLMConfiguration = .default,
        urlSession: URLSession? = nil,
        model: Model = .kimi_k2_5
    ) {
        self.apiKeyManager = apiKeyManager
        self.configuration = configuration
        self.model = model
        
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
                    guard let apiKey = try? await apiKeyManager.getKey(for: .baiduqianfan) else {
                        throw LLMServiceError.apiKeyMissing
                    }
                    
                    // Build request
                    let request = try buildRequest(
                        message: message,
                        context: context,
                        history: history,
                        apiKey: apiKey
                    )
                    
                    logger.info("Sending message to Baidu Qianfan API (model: \(self.model.rawValue))")
                    
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
            guard (try? await apiKeyManager.getKey(for: .baiduqianfan)) != nil else {
                return .notConfigured
            }
            
            // Make a simple test request
            let stream = sendMessage(
                "test",
                context: ConversationContext(portfolioName: nil, positions: [], riskProfile: nil, targetAllocation: nil),
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
            
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
    
    func clearHistory() {
        // No-op for stateless service
    }
    
    // MARK: - Request Building
    
    private func buildRequest(
        message: String,
        context: ConversationContext,
        history: [ChatMessage],
        apiKey: String
    ) throws -> URLRequest {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "model": model.rawValue,
            "messages": buildMessages(message: message, context: context, history: history),
            "temperature": configuration.temperature,
            "max_tokens": configuration.maxTokens,
            "stream": true
        ]
        
        // Note: Thinking mode is automatic for these models
        // budgetTokens is handled internally by Baidu Qianfan
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    private func buildMessages(
        message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        
        // System message
        let systemContent = SystemPrompts.buildContextString(context: context)
        messages.append(["role": "system", "content": systemContent])
        
        // History
        for msg in history.suffix(configuration.maxContextLength) {
            messages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        
        // Current message
        messages.append(["role": "user", "content": message])
        
        return messages
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
                if isRetryableError(error) && attempt < configuration.maxRetries - 1 {
                    let delay = configuration.retryDelay * Double(attempt + 1)
                    logger.warning("Request failed, retrying in \(delay)s (attempt \(attempt + 1)/\(configuration.maxRetries))")
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

// MARK: - System Prompts (Shared with KimiService)

enum SystemPrompts {
    static let basePrompt = """
    You are a professional investment advisor specializing in portfolio management and rebalancing strategies. 
    You provide clear, actionable advice based on modern portfolio theory and risk management principles.
    Always consider the user's portfolio context when providing recommendations.
    
    Key principles:
    - Explain your reasoning clearly
    - Consider risk tolerance and investment goals
    - Provide specific, actionable recommendations
    - Acknowledge limitations and risks
    """
    
    static func buildContextString(context: ConversationContext) -> String {
        var contextStr = basePrompt + "\n\n"
        
        if let name = context.portfolioName {
            contextStr += "Portfolio: \(name)\n"
        }
        
        if !context.positions.isEmpty {
            contextStr += "\nCurrent Positions:\n"
            for pos in context.positions {
                contextStr += "- \(pos.symbol): \(pos.shares) shares @ $\(String(format: "%.2f", pos.currentValue))\n"
            }
        }
        
        if let risk = context.riskProfile {
            contextStr += "\nRisk Profile: \(risk)\n"
        }
        
        if let allocation = context.targetAllocation, !allocation.isEmpty {
            contextStr += "\nTarget Allocation:\n"
            for (symbol, weight) in allocation.sorted(by: { $0.key < $1.key }) {
                contextStr += "- \(symbol): \(Int(weight * 100))%\n"
            }
        }
        
        return contextStr
    }
}

// MARK: - LLMConfiguration Extension

extension LLMConfiguration {
    static let `default` = LLMConfiguration(
        model: "kimi-k2.5",
        temperature: 0.7,
        maxTokens: 4096,
        topP: 1.0,
        requestTimeout: 60.0,
        maxRetries: 3,
        retryDelay: 2.0,
        maxContextLength: 50
    )
}
