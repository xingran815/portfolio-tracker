//
//  LLMServiceProtocol.swift
//  portfolio_tracker
//
//  Protocol for LLM chat services
//

import Foundation

/// Errors from LLM service
enum LLMServiceError: LocalizedError, Sendable {
    case networkError(underlying: Error)
    case invalidResponse
    case rateLimited
    case invalidAPIKey
    case contextTooLong
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .rateLimited:
            return "Rate limit exceeded. Please wait a moment."
        case .invalidAPIKey:
            return "Invalid API key. Please check your settings."
        case .contextTooLong:
            return "Message too long. Please shorten your input."
        }
    }
}

/// Validation result for API key
enum APIKeyValidationResult: Sendable {
    case valid
    case invalid(String)
    case networkError(String)
}

/// Protocol for LLM chat services
protocol LLMServiceProtocol: Actor {
    /// Sends a message and returns streaming response
    /// - Parameters:
    ///   - text: User message
    ///   - context: Additional context (e.g., portfolio summary)
    /// - Returns: Async stream of response chunks or errors
    func sendMessage(
        _ text: String,
        context: String
    ) -> AsyncStream<Result<String, LLMServiceError>>
    
    /// Validates the API key
    /// - Returns: Validation result
    func validateAPIKey() async -> APIKeyValidationResult
    
    /// Clears conversation history
    func clearHistory()
}

// MARK: - Chat Message Model

/// A chat message
struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    
    enum MessageRole: String, Codable, Sendable {
        case user
        case assistant
        case system
    }
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
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
        _ text: String,
        context: String
    ) -> AsyncStream<Result<String, LLMServiceError>> {
        AsyncStream { continuation in
            Task {
                // Store user message
                let userMessage = ChatMessage(role: .user, content: text)
                messages.append(userMessage)
                
                if shouldFail {
                    continuation.yield(.failure(.networkError(underlying: NSError(domain: "Mock", code: -1))))
                    continuation.finish()
                    return
                }
                
                // Generate mock response
                let response = generateMockResponse(for: text, context: context)
                
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
        return shouldFail ? .invalid("Invalid mock key") : .valid
    }
    
    func clearHistory() {
        messages.removeAll()
    }
    
    func getMessages() -> [ChatMessage] {
        messages
    }
    
    private func generateMockResponse(for text: String, context: String) -> String {
        let lowercased = text.lowercased()
        
        if lowercased.contains("rebalance") || lowercased.contains("再平衡") {
            return "Based on your portfolio context, I recommend reviewing your allocation. Your current drift shows some positions are overweight. Would you like me to analyze specific positions?"
        } else if lowercased.contains("price") || lowercased.contains("价格") {
            return "I can help you track prices, but you'll need to configure your Alpha Vantage API key in Settings first. Once configured, prices will update automatically."
        } else if lowercased.contains("help") || lowercased.contains("帮助") {
            return "I'm your AI portfolio assistant. I can help you:\n\n1. **Analyze portfolio drift** - Check if your allocation matches targets\n2. **Suggest rebalancing** - Get recommendations for trades\n3. **Answer questions** - Ask about positions, performance, or strategy\n4. **Review allocations** - Compare current vs target weights\n\nWhat would you like to discuss?"
        } else {
            return "Thank you for your message. I understand you're asking about \"\(text)\". \n\nWith your portfolio context (\(context.count) characters), I can provide personalized advice. Could you clarify what specific aspect you'd like help with?\n\n- Portfolio analysis\n- Rebalancing suggestions\n- Risk assessment\n- General investment questions"
        }
    }
}
