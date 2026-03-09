//
//  ChatViewModel.swift
//  portfolio_tracker
//
//  ViewModel for chat interface
//

import Foundation
import os.log

/// ViewModel for managing chat conversations
@MainActor
@Observable
final class ChatViewModel {
    
    // MARK: - Properties
    
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    
    private let llmService: any LLMServiceProtocol
    private let portfolio: Portfolio?
    private var currentTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "ChatViewModel")
    
    // MARK: - Initialization
    
    init(
        llmService: any LLMServiceProtocol = KimiService(),
        portfolio: Portfolio? = nil
    ) {
        self.llmService = llmService
        self.portfolio = portfolio
    }
    
    // MARK: - Public Methods
    
    /// Sends a message and receives streaming response
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let userMessage = ChatMessage(role: .user, content: inputText)
        messages.append(userMessage)
        
        let messageToSend = inputText
        inputText = ""
        isLoading = true
        errorMessage = nil
        
        currentTask = Task {
            await streamResponse(to: messageToSend)
        }
    }
    
    /// Cancels the current streaming request
    func cancelStreaming() {
        currentTask?.cancel()
        isLoading = false
    }
    
    /// Clears the conversation history
    func clearConversation() {
        cancelStreaming()
        messages.removeAll()
        errorMessage = nil
    }
    
    /// Checks if LLM is configured
    func isConfigured() async -> Bool {
        do {
            return try await llmService.validateAPIKey()
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func streamResponse(to message: String) async {
        // Build context from portfolio
        let context = buildContext()
        
        // Create assistant message placeholder
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1
        
        // Stream response
        let stream = llmService.sendMessage(
            message,
            context: context,
            history: messages.dropLast() // Exclude current assistant message
        )
        
        var fullResponse = ""
        
        do {
            for try await chunk in stream {
                // Check for cancellation
                if Task.isCancelled {
                    break
                }
                
                fullResponse += chunk
                messages[assistantIndex] = ChatMessage(
                    id: assistantMessage.id,
                    role: .assistant,
                    content: fullResponse
                )
            }
            
            logger.info("Received response: \(fullResponse.prefix(100))...")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Streaming error: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    private func buildContext() -> ConversationContext {
        guard let portfolio = portfolio else {
            return ConversationContext(
                portfolioName: nil,
                positions: [],
                riskProfile: nil,
                targetAllocation: nil
            )
        }
        
        let positions = portfolio.positions?.compactMap { position -> ConversationContext.PositionSummary? in
            guard let position = position as? Position else { return nil }
            return ConversationContext.PositionSummary(
                symbol: position.symbol ?? "Unknown",
                shares: position.shares,
                currentValue: position.currentValue
            )
        } ?? []
        
        return ConversationContext(
            portfolioName: portfolio.name,
            positions: positions,
            riskProfile: portfolio.riskProfile?.displayName,
            targetAllocation: portfolio.targetAllocation
        )
    }
}

// MARK: - Position Value Helper

private extension Position {
    var currentValue: Double {
        return shares * currentPrice
    }
}
