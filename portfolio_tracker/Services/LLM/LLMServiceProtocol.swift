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
    let reasoningContent: String?
    let timestamp: Date
    
    init(id: UUID = UUID(), role: MessageRole, content: String, reasoningContent: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.timestamp = timestamp
    }
}

/// Type of streaming chunk
enum StreamChunkType: Sendable {
    case reasoning
    case content
}

/// A chunk from the streaming response
struct StreamChunk: Sendable {
    let content: String
    let type: StreamChunkType
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
    /// - Returns: AsyncStream of response chunks with type info
    func sendMessage(
        _ message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> AsyncStream<Result<StreamChunk, LLMServiceError>>
    
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
        model: "k2p5",
        temperature: 0.7,
        maxTokens: 8192,
        topP: 0.9,
        requestTimeout: 60.0,
        maxRetries: 3,
        retryDelay: 1.0,
        maxContextLength: 200000
    )
}


