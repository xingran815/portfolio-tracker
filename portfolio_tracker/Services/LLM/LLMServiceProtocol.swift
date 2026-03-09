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

/// Errors that can occur during LLM operations
enum LLMServiceError: LocalizedError {
    case apiKeyMissing
    case invalidAPIKey
    case networkError(underlying: Error)
    case rateLimited
    case invalidResponse
    case decodingError(underlying: Error)
    case contextTooLong
    case serviceUnavailable
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Kimi API key not configured. Please add your API key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your Kimi API key in Settings."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limit exceeded. Please wait a moment before trying again."
        case .invalidResponse:
            return "Invalid response from AI service"
        case .decodingError:
            return "Failed to decode AI response"
        case .contextTooLong:
            return "Conversation context is too long. Please start a new chat."
        case .serviceUnavailable:
            return "AI service is temporarily unavailable"
        case .cancelled:
            return "Request was cancelled"
        }
    }
}

/// Protocol for LLM services
protocol LLMServiceProtocol: Sendable {
    /// Sends a message and returns streaming response
    /// - Parameters:
    ///   - message: User's message
    ///   - context: Portfolio context for personalized responses
    ///   - history: Previous conversation history
    /// - Returns: AsyncStream of response chunks
    @Sendable func sendMessage(
        _ message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> AsyncStream<String>
    
    /// Validates the API key by making a test request
    @Sendable func validateAPIKey() async throws -> Bool
}

/// Configuration for LLM requests
struct LLMConfiguration: Sendable {
    let model: String
    let temperature: Double
    let maxTokens: Int
    let topP: Double
    
    static let `default` = LLMConfiguration(
        model: "moonshot-v1-8k",
        temperature: 0.7,
        maxTokens: 2048,
        topP: 0.9
    )
}
