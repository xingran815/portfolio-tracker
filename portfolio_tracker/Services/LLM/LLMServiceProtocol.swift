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
    
    struct PositionSummary: Sendable {
        let symbol: String
        let shares: Double
        let currentValue: Double
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
            return "Kimi API key not configured. Please add your API key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your Kimi API key in Settings."
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

// MARK: - Mock Implementation

/// Mock LLM service for testing and UI development
actor MockLLMService: LLMServiceProtocol {
    
    private var messages: [ChatMessage] = []
    private let shouldFail: Bool
    private let delay: Duration
    
    init(shouldFail: Bool = false, delay: Duration = .milliseconds(100)) {
        self.shouldFail = shouldFail
        self.delay = delay
    }
    
    func sendMessage(
        _ message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> AsyncStream<Result<String, LLMServiceError>> {
        AsyncStream { continuation in
            Task {
                // Store user message
                let userMessage = ChatMessage(role: .user, content: message)
                messages.append(userMessage)
                
                if shouldFail {
                    continuation.yield(.failure(.networkError("Mock error")))
                    continuation.finish()
                    return
                }
                
                // Generate mock response
                let response = generateMockResponse(for: message, context: context)
                
                // Stream response word by word
                let words = response.split(separator: " ")
                for (index, word) in words.enumerated() {
                    try? await Task.sleep(for: delay)
                    let chunk = index == 0 ? String(word) : " \(word)"
                    continuation.yield(.success(chunk))
                }
                
                // Store assistant message
                let assistantMessage = ChatMessage(role: .assistant, content: response)
                messages.append(assistantMessage)
                
                continuation.finish()
            }
        }
    }
    
    func validateAPIKey() async -> APIKeyValidationResult {
        try? await Task.sleep(for: .milliseconds(300))
        return shouldFail ? .invalid : .valid
    }
    
    func clearHistory() {
        messages.removeAll()
    }
    
    func getMessages() -> [ChatMessage] {
        messages
    }
    
    private func generateMockResponse(for text: String, context: ConversationContext) -> String {
        let lowercased = text.lowercased()
        
        if lowercased.contains("rebalance") || lowercased.contains("再平衡") {
            return "Based on your portfolio context, I recommend reviewing your allocation. Your current drift shows some positions are overweight. Would you like me to analyze specific positions?"
        } else if lowercased.contains("price") || lowercased.contains("价格") {
            return "I can help you track prices, but you'll need to configure your Alpha Vantage API key in Settings first. Once configured, prices will update automatically."
        } else if lowercased.contains("help") || lowercased.contains("帮助") {
            return "I'm your AI portfolio assistant. I can help you:\n\n1. **Analyze portfolio drift** - Check if your allocation matches targets\n2. **Suggest rebalancing** - Get recommendations for trades\n3. **Answer questions** - Ask about positions, performance, or strategy\n4. **Review allocations** - Compare current vs target weights\n\nWhat would you like to discuss?"
        } else {
            return "Thank you for your message. I understand you're asking about \"\(text)\". \n\nWith your portfolio context, I can provide personalized advice. Could you clarify what specific aspect you'd like help with?\n\n- Portfolio analysis\n- Rebalancing suggestions\n- Risk assessment\n- General investment questions"
        }
    }
}
