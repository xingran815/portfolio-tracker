//
//  ChatViewModel.swift
//  portfolio_tracker
//
//  ViewModel for AI chat with portfolio context
//

import SwiftUI
import os.log

/// ViewModel for managing AI chat conversations
@MainActor
@Observable
final class ChatViewModel {
    
    // MARK: - Properties
    
    /// Chat messages
    var messages: [ChatMessage] = []
    
    /// Current user input
    var inputText = ""
    
    /// Whether AI is generating response
    var isLoading = false
    
    /// Error message
    var errorMessage: String?
    
    /// Whether to include portfolio context with messages
    var includePortfolioContext = true
    
    /// Whether to show reasoning/thinking process
    var showReasoning = false
    
    /// Current portfolio for context (CoreData object)
    private var portfolio: Portfolio?
    
    /// View-safe portfolio data
    private(set) var portfolioData: PortfolioViewData?
    
    /// Chat history persistence key
    private var chatHistoryKey: String {
        if let portfolioId = portfolio?.id?.uuidString {
            return "chat_history_\(portfolioId)"
        }
        return "chat_history_global"
    }
    
    // MARK: - Dependencies
    
    private var llmService: any LLMServiceProtocol
    private var currentTask: Task<Void, Never>?
    private var currentAssistantMessageId: UUID?
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "ChatViewModel")
    
    /// Whether the service is using real API or mock
    var isUsingRealAPI: Bool {
        !(llmService is MockLLMService)
    }
    
    // MARK: - Initialization
    
    init(
        llmService: (any LLMServiceProtocol)? = nil,
        portfolio: Portfolio? = nil
    ) {
        self.llmService = llmService ?? MockLLMService()
        self.portfolio = portfolio
        loadChatHistory()
        addWelcomeMessageIfNeeded()
        
        // Check for real API key and switch if available
        Task {
            await autoSwitchToRealServiceIfAvailable()
        }
    }
    
    // MARK: - Public Methods
    
    /// Sets the current portfolio for context
    /// - Parameter portfolio: Portfolio to include in context
    func setPortfolio(_ portfolio: Portfolio?) {
        // Save current chat history if portfolio is changing
        if self.portfolio?.id != portfolio?.id {
            saveChatHistory()
            self.portfolio = portfolio
            self.portfolioData = portfolio.map { PortfolioViewData.from($0) }
            loadChatHistory()
        }
    }
    
    /// Sets the current portfolio using view data
    /// - Parameter portfolioData: Portfolio view data
    func setPortfolio(_ portfolioData: PortfolioViewData?) {
        // Save current chat history if portfolio is changing
        if self.portfolioData?.id != portfolioData?.id {
            saveChatHistory()
            self.portfolioData = portfolioData
            loadChatHistory()
        }
    }
    
    /// Sends user message and streams AI response
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
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
    
    /// Clears chat history
    func clearConversation() {
        cancelStreaming()
        messages.removeAll()
        errorMessage = nil
        currentAssistantMessageId = nil
        Task {
            await llmService.clearHistory()
        }
        addWelcomeMessageIfNeeded()
        saveChatHistory()
        logger.info("Cleared chat history")
    }
    
    /// Regenerates the last AI response
    func regenerateLastResponse() {
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }
        
        // Remove the last assistant message if exists
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant {
            messages.remove(at: lastIndex)
        }
        
        isLoading = true
        errorMessage = nil
        currentAssistantMessageId = nil
        
        currentTask = Task {
            await streamResponse(to: lastUserMessage.content)
        }
    }
    
    /// Copies message content to clipboard
    /// - Parameter message: Message to copy
    func copyToClipboard(_ message: ChatMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
    }
    
    /// Checks if LLM is configured
    func isConfigured() async -> APIKeyValidationResult {
        await llmService.validateAPIKey()
    }
    
    /// Automatically switches to real Kimi API service if API key is available
    /// Called during initialization
    private func autoSwitchToRealServiceIfAvailable() async {
        let apiKeyManager = APIKeyManager.shared
        if await apiKeyManager.hasKey(for: .kimi) {
            llmService = KimiService(apiKeyManager: apiKeyManager)
            logger.info("Auto-switched to real Kimi API service on initialization")
        }
    }
    
    /// Switches to real Kimi API service if API key is available
    /// Call this when API key is added in settings
    func switchToRealService() async {
        guard !isUsingRealAPI else { return }
        
        let apiKeyManager = APIKeyManager.shared
        if await apiKeyManager.hasKey(for: .kimi) {
            llmService = KimiService(apiKeyManager: apiKeyManager)
            logger.info("Switched to real Kimi API service")
        }
    }
    
    /// Switches back to mock service (for testing)
    func switchToMockService() {
        llmService = MockLLMService()
        logger.info("Switched to mock service")
    }
    
    /// Saves chat history to UserDefaults
    func saveChatHistory() {
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: chatHistoryKey)
            logger.debug("Saved chat history for \(self.chatHistoryKey)")
        } catch {
            logger.error("Failed to save chat history: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func streamResponse(to message: String) async {
        let context = includePortfolioContext ? buildContext() : ConversationContext(
            portfolioName: nil,
            positions: [],
            riskProfile: nil,
            targetAllocation: nil
        )
        
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        let assistantId = assistantMessage.id
        currentAssistantMessageId = assistantId
        messages.append(assistantMessage)
        
        let validHistory = messages.filter { !$0.content.isEmpty && $0.id != assistantId }
        let stream = await llmService.sendMessage(
            message,
            context: context,
            history: validHistory
        )
        
        var fullResponse = ""
        var fullReasoning = ""
        
        for await result in stream {
            if Task.isCancelled {
                break
            }
            
            switch result {
            case .success(let chunk):
                switch chunk.type {
                case .content:
                    fullResponse += chunk.content
                case .reasoning:
                    fullReasoning += chunk.content
                }
                
                updateAssistantMessage(
                    id: assistantId,
                    content: fullResponse,
                    reasoning: showReasoning ? fullReasoning : nil
                )
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                logger.error("Streaming error: \(error.localizedDescription)")
                removeMessage(id: assistantId)
                currentAssistantMessageId = nil
                isLoading = false
                return
            }
        }
        
        logger.info("Received response: \(fullResponse.prefix(100))...")
        currentAssistantMessageId = nil
        isLoading = false
        
        saveChatHistory()
    }
    
    /// Safely updates assistant message by ID (prevents race conditions)
    private func updateAssistantMessage(id: UUID, content: String, reasoning: String?) {
        guard currentAssistantMessageId == id else { return }
        
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = ChatMessage(
                id: id,
                role: .assistant,
                content: content,
                reasoningContent: reasoning
            )
        }
    }
    
    /// Removes a message by ID
    private func removeMessage(id: UUID) {
        messages.removeAll { $0.id == id }
    }
    
    private func loadChatHistory() {
        guard let data = UserDefaults.standard.data(forKey: chatHistoryKey) else {
            messages = []
            addWelcomeMessageIfNeeded()
            return
        }
        
        do {
            messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            if messages.isEmpty {
                addWelcomeMessageIfNeeded()
            }
            logger.debug("Loaded chat history for \(self.chatHistoryKey)")
        } catch {
            logger.error("Failed to load chat history: \(error.localizedDescription)")
            messages = []
            addWelcomeMessageIfNeeded()
        }
    }
    
    private func addWelcomeMessageIfNeeded() {
        guard messages.isEmpty else { return }
        
        let welcomeMessage = ChatMessage(
            role: .assistant,
            content: "Hello! I'm your AI portfolio assistant. I can help you analyze your portfolio, suggest rebalancing strategies, and answer investment questions.\n\nHow can I help you today?"
        )
        messages.append(welcomeMessage)
    }
    
    private func buildContext() -> ConversationContext {
        // Prefer CoreData object if available for full context
        if let portfolio = portfolio {
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
        
        // Fallback to view data
        guard let portfolioData = portfolioData else {
            return ConversationContext(
                portfolioName: nil,
                positions: [],
                riskProfile: nil,
                targetAllocation: nil
            )
        }
        
        return ConversationContext(
            portfolioName: portfolioData.name,
            positions: [], // View data doesn't include individual positions
            riskProfile: portfolioData.riskProfile.displayName,
            targetAllocation: portfolioData.targetAllocation
        )
    }
}
