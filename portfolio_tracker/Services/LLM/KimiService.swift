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
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMServiceError.invalidResponse
                    }
                    
                    switch httpResponse.statusCode {
                    case 200:
                        break
                    case 401:
                        throw LLMServiceError.invalidAPIKey
                    case 429:
                        throw LLMServiceError.rateLimited
                    case 500...599:
                        throw LLMServiceError.serviceUnavailable
                    default:
                        throw LLMServiceError.invalidResponse
                    }
                    
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
        // Build URL based on endpoint
        let path = endpoint == .kimiWeb ? "/chat/completions" : "/chat/completions"
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw LLMServiceError.invalidResponse
        }
        
        // Build messages
        var messages: [[String: String]] = []
        
        // Add system prompt
        let systemPrompt = SystemPrompts.portfolioAdvisor(context: context)
        messages.append([
            "role": "system",
            "content": systemPrompt
        ])
        
        // Add history (limit to last 10 messages to avoid token limit)
        for chatMessage in history.suffix(10) {
            messages.append([
                "role": chatMessage.role.rawValue,
                "content": chatMessage.content
            ])
        }
        
        // Add user message
        messages.append([
            "role": "user",
            "content": message
        ])
        
        // Build request body
        let modelName: String
        switch endpoint {
        case .kimiWeb, .kimiCoding:
            modelName = "kimi-latest"
        case .custom:
            modelName = "claude-3-haiku-20240307"  // Try Claude for custom endpoints
        case .moonshot:
            modelName = configuration.model
        }
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": configuration.temperature,
            "max_tokens": configuration.maxTokens,
            "top_p": configuration.topP,
            "stream": true
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Authentication based on endpoint
        switch endpoint {
        case .moonshot:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .kimiWeb:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .kimiCoding:
            // Kimi Coding API requires specific headers
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("claude-code/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("claude-code", forHTTPHeaderField: "X-Client-Name")
        case .custom:
            // For custom endpoints, try multiple auth methods
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        // Add custom headers if provided
        if let headers = customHeaders {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
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
        var prompt = """You are a professional investment advisor specializing in portfolio management and rebalancing strategies.

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
                prompt += "\n- \(position.symbol): \(String(format: "%.2f", position.shares)) shares, $")
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
