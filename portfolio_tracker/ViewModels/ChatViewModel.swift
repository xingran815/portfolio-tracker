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
    
    // Track current assistant message ID for safe updates
    private var currentAssistantMessageId: UUID?
    
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
        currentAssistantMessageId = nil
        
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
        currentAssistantMessageId = nil
    }
    
    /// Checks if LLM is configured
    func isConfigured() async -> APIKeyValidationResult {
        await llmService.validateAPIKey()
    }
    
    // MARK: - Private Methods
    
    private func streamResponse(to message: String) async {
        // Build context from portfolio
        let context = buildContext()
        
        // Create assistant message placeholder with unique ID
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        let assistantId = assistantMessage.id
        currentAssistantMessageId = assistantId
        messages.append(assistantMessage)
        
        // Stream response
        let stream = await llmService.sendMessage(
            message,
            context: context,
            history: Array(messages.dropLast()) // Exclude current assistant message
        )
        
        var fullResponse = ""
        
        for await result in stream {
            // Check for cancellation
            if Task.isCancelled {
                break
            }
            
            switch result {
            case .success(let chunk):
                fullResponse += chunk
                updateAssistantMessage(id: assistantId, content: fullResponse)
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                logger.error("Streaming error: \(error.localizedDescription)")
                // Remove the empty assistant message on error
                removeMessage(id: assistantId)
                currentAssistantMessageId = nil
                isLoading = false
                return
            }
        }
        
        logger.info("Received response: \(fullResponse.prefix(100))...")
        currentAssistantMessageId = nil
        isLoading = false
    }
    
    /// Safely updates assistant message by ID (prevents race conditions)
    private func updateAssistantMessage(id: UUID, content: String) {
        // Only update if this is still the current assistant message
        guard currentAssistantMessageId == id else { return }
        
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = ChatMessage(
                id: id,
                role: .assistant,
                content: content
            )
        }
    }
    
    /// Removes a message by ID
    private func removeMessage(id: UUID) {
        messages.removeAll { $0.id == id }
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
        
        // Get positions from NSSet
        let positionSet = portfolio.positions as? Set<Position> ?? []
        let positions = positionSet.map { position -> ConversationContext.PositionSummary in
            ConversationContext.PositionSummary(
                symbol: position.symbol ?? "Unknown",
                shares: position.shares,
                currentValue: position.currentPrice * position.shares
            )
        }
        
        return ConversationContext(
            portfolioName: portfolio.name,
            positions: positions,
            riskProfile: portfolio.riskProfile.displayName,
            targetAllocation: portfolio.targetAllocation
        )
    }
}

// MARK: - Factory Extension

extension ChatViewModel {
    /// Creates a ChatViewModel with mock LLM service for testing
    static func mock(portfolio: Portfolio? = nil) -> ChatViewModel {
        ChatViewModel(llmService: MockLLMService(), portfolio: portfolio)
    }
}
