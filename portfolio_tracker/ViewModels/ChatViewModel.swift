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
    var isGenerating = false
    
    /// Streaming response text being built
    var streamingResponse = ""
    
    /// Error message
    var errorMessage: String?
    
    /// Show error alert
    var showError = false
    
    /// Whether to include portfolio context with messages
    var includePortfolioContext = true
    
    /// Current portfolio for context
    var currentPortfolio: Portfolio?
    
    /// Chat history persistence key
    private var chatHistoryKey: String {
        if let portfolioId = currentPortfolio?.id?.uuidString {
            return "chat_history_\(portfolioId)"
        }
        return "chat_history_global"
    }
    
    // MARK: - Dependencies
    
    private let llmService: any LLMServiceProtocol
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "ChatViewModel")
    
    // MARK: - Initialization
    
    init(llmService: any LLMServiceProtocol = MockLLMService()) {
        self.llmService = llmService
        loadChatHistory()
        addSystemMessage()
    }
    
    // MARK: - Public Methods
    
    /// Sets the current portfolio for context
    /// - Parameter portfolio: Portfolio to include in context
    func setPortfolio(_ portfolio: Portfolio?) {
        // Save current chat history if portfolio is changing
        if currentPortfolio?.id != portfolio?.id {
            saveChatHistory()
            currentPortfolio = portfolio
            loadChatHistory()
        }
    }
    
    /// Sends user message and streams AI response
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = ChatMessage(role: .user, content: inputText)
        messages.append(userMessage)
        
        let messageText = inputText
        inputText = ""
        isGenerating = true
        streamingResponse = ""
        
        let context = includePortfolioContext ? buildPortfolioContext() : ""
        
        Task {
            await streamResponse(for: messageText, context: context)
        }
    }
    
    /// Clears chat history
    func clearHistory() {
        messages.removeAll()
        Task {
            await llmService.clearHistory()
        }
        addSystemMessage()
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
        
        isGenerating = true
        streamingResponse = ""
        
        let context = includePortfolioContext ? buildPortfolioContext() : ""
        
        Task {
            await streamResponse(for: lastUserMessage.content, context: context)
        }
    }
    
    /// Copies message content to clipboard
    /// - Parameter message: Message to copy
    func copyToClipboard(_ message: ChatMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
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
    
    private func streamResponse(for text: String, context: String) async {
        let stream = await llmService.sendMessage(text, context: context)
        
        do {
            for try await result in stream {
                switch result {
                case .success(let chunk):
                    streamingResponse += chunk
                case .failure(let error):
                    showError(message: error.localizedDescription)
                    isGenerating = false
                    return
                }
            }
            
            // Add completed message
            let assistantMessage = ChatMessage(role: .assistant, content: streamingResponse)
            messages.append(assistantMessage)
            streamingResponse = ""
            isGenerating = false
            
            // Save history after each complete exchange
            saveChatHistory()
            
        } catch {
            showError(message: error.localizedDescription)
            isGenerating = false
        }
    }
    
    private func loadChatHistory() {
        guard let data = UserDefaults.standard.data(forKey: chatHistoryKey) else {
            messages = []
            addSystemMessage()
            return
        }
        
        do {
            messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            if messages.isEmpty {
                addSystemMessage()
            }
            logger.debug("Loaded chat history for \(self.chatHistoryKey)")
        } catch {
            logger.error("Failed to load chat history: \(error.localizedDescription)")
            messages = []
            addSystemMessage()
        }
    }
    
    private func addSystemMessage() {
        let welcomeMessage = ChatMessage(
            role: .assistant,
            content: "Hello! I'm your AI portfolio assistant. I can help you analyze your portfolio, suggest rebalancing strategies, and answer investment questions.\n\nHow can I help you today?"
        )
        messages.append(welcomeMessage)
    }
    
    private func buildPortfolioContext() -> String {
        guard let portfolio = currentPortfolio else {
            return "No portfolio selected."
        }
        
        var context = "Portfolio: \(portfolio.name ?? "Unnamed")\n"
        context += "Total Value: $\(String(format: "%.2f", portfolio.totalValue))\n"
        context += "Risk Profile: \(portfolio.riskProfile.displayName)\n"
        context += "Expected Return: \(String(format: "%.1f", portfolio.expectedReturn * 100))%\n"
        context += "Max Drawdown: \(String(format: "%.1f", portfolio.maxDrawdown * 100))%\n"
        context += "Rebalancing Frequency: \(portfolio.rebalancingFrequency.displayName)\n\n"
        
        let positionSet = portfolio.positions as? Set<Position> ?? []
        if !positionSet.isEmpty {
            context += "Current Positions:\n"
            for position in positionSet.sorted(by: { ($0.currentValue ?? 0) > ($1.currentValue ?? 0) }) {
                let symbol = position.symbol ?? "Unknown"
                let value = position.currentValue ?? 0
                let weight = portfolio.totalValue > 0 ? value / portfolio.totalValue : 0
                context += "- \(symbol): \(String(format: "%.0f", position.shares)) shares, $\(String(format: "%.2f", value)) (\(String(format: "%.1f", weight * 100))%)\n"
            }
            
            let targetAllocation = portfolio.targetAllocation
            if !targetAllocation.isEmpty {
                context += "\nTarget Allocation:\n"
                for (symbol, weight) in targetAllocation.sorted(by: { $0.key < $1.key }) {
                    context += "- \(symbol): \(String(format: "%.1f", weight * 100))%\n"
                }
            }
        }
        
        return context
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
