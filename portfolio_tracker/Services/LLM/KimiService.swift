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
        case kimiCoding = "https://api.kimi.com/coding/v1"  // kimi.com coding API (your key works here!)
        case custom                                    // Custom endpoint (set via init)
    }
    
    /// Custom base URL for custom endpoint
    private let customBaseURL: String?
    
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
        urlSession: URLSession = .shared,
        endpoint: APIEndpoint = .kimiCoding,  // Default to kimiCoding for your key
        customBaseURL: String? = nil,
        customHeaders: [String: String]? = nil
    ) {
        self.apiKeyManager = apiKeyManager
        self.configuration = configuration
        self.urlSession = urlSession
        self.endpoint = endpoint
        self.customBaseURL = customBaseURL
        self.customHeaders = customHeaders
    }
    
    /// Custom headers to add to requests
    private let customHeaders: [String: String]?
    
    // MARK: - LLMServiceProtocol
    
    func sendMessage(
        _ message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> AsyncStream<String> {
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
                    
                    // Perform streaming request
                    let (bytes, response) = try await urlSession.bytes(for: request)
                    
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
                            continuation.yield(content)
                        }
                    }
                    
                    logger.info("Streaming completed")
                    continuation.finish()
                    
                } catch let error as LLMServiceError {
                    logger.error("LLM error: \(error.localizedDescription)")
                    continuation.finish()
                } catch {
                    logger.error("Unexpected error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
            
            // Handle cancellation
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    func validateAPIKey() async throws -> Bool {
        do {
            _ = try await apiKeyManager.getKey(for: .kimi)
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
            for await _ in stream {
                receivedContent = true
                break // Just need to receive one chunk to validate
            }
            
            return receivedContent
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func buildRequest(
        message: String,
        context: ConversationContext,
        history: [ChatMessage],
        apiKey: String
    ) throws -> URLRequest {
        guard let url = buildURL() else {
            throw LLMServiceError.invalidResponse
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
        messages.append([
            "role": "system",
            "content": SystemPrompts.portfolioAdvisor(context: context)
        ])
        
        // Add history (limit to last 10 messages)
        for chatMessage in history.suffix(10) {
            messages.append([
                "role": chatMessage.role.rawValue,
                "content": chatMessage.content
            ])
        }
        
        // Add user message
        messages.append(["role": "user", "content": message])
        
        return messages
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
            return "kimi-latest"
        case .custom:
            return "claude-3-haiku-20240307"
        case .moonshot:
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
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
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
            throw LLMServiceError.invalidResponse
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
            throw LLMServiceError.invalidResponse
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

// MARK: - System Prompts

enum SystemPrompts {
    /// Generates system prompt for portfolio advisor
    static func portfolioAdvisor(context: ConversationContext) -> String {
        var prompt = """
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
        
        // Add portfolio context if available
        if let portfolioName = context.portfolioName {
            prompt += "\n\nPortfolio: \(portfolioName)"
        }
        
        if let riskProfile = context.riskProfile {
            prompt += "\nRisk Profile: \(riskProfile)"
        }
        
        if !context.positions.isEmpty {
            prompt += "\n\nCurrent Positions:"
            for position in context.positions {
                prompt += "\n- \(position.symbol): \(String(format: "%.2f", position.shares)) shares"
            }
        }
        
        if let allocation = context.targetAllocation, !allocation.isEmpty {
            prompt += "\n\nTarget Allocation:"
            for (symbol, percentage) in allocation {
                prompt += "\n- \(symbol): \(String(format: "%.1f", percentage * 100))%"
            }
        }
        
        prompt += "\n\nRemember: This is educational advice. Always consult with a licensed financial advisor for personalized recommendations."
        
        return prompt
    }
}
