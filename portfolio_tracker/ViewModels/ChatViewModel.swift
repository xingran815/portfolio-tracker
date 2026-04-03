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
    
    nonisolated deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
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
        
        // Listen for LLM configuration changes
        setupLLMChangeObservers()
        
        // Check for real API key and switch if available
        Task {
            await autoSwitchToRealServiceIfAvailable()
        }
    }
    
    /// Sets up notification observers for LLM configuration changes
    private func setupLLMChangeObservers() {
        // Listen for model changes
        NotificationCenter.default.addObserver(
            forName: .llmModelDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleLLMConfigurationChange()
            }
        }
        
        // Listen for provider changes
        NotificationCenter.default.addObserver(
            forName: .llmProviderDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleLLMConfigurationChange()
            }
        }
    }
    
    /// Handles LLM model or provider changes by refreshing the service
    private func handleLLMConfigurationChange() async {
        llmService = await LLMServiceFactory.shared.refreshService()
        logger.info("Refreshed LLM service due to configuration change")
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
    
    /// Automatically switches to real LLM service if API key is available
    /// Called during initialization
    private func autoSwitchToRealServiceIfAvailable() async {
        llmService = await LLMServiceFactory.shared.getService()
        logger.info("Auto-switched to LLM service based on provider preference")
    }
    
    /// Switches to a different LLM provider
    /// - Parameter provider: The provider to switch to
    func switchProvider(_ provider: LLMProvider) async {
        await LLMServiceFactory.shared.setProvider(provider)
        llmService = await LLMServiceFactory.shared.getService()
        logger.info("Switched to \(provider.rawValue) provider")
    }
    
    /// Switches Baidu Qianfan model
    /// - Parameter model: The model to use
    func switchBaiduModel(_ model: BaiduQianfanService.Model) async {
        await LLMServiceFactory.shared.setBaiduQianfanModel(model)
        llmService = await LLMServiceFactory.shared.refreshService()
        logger.info("Switched to Baidu Qianfan model: \(model.rawValue)")
    }
    
    /// Gets the current LLM provider
    /// - Returns: The current provider
    func getCurrentProvider() async -> LLMProvider {
        await LLMServiceFactory.shared.getProvider()
    }
    
    /// Gets the selected Baidu Qianfan model
    /// - Returns: The selected model
    func getBaiduModel() async -> BaiduQianfanService.Model {
        await LLMServiceFactory.shared.getBaiduQianfanModel()
    }
    
    /// Switches to real LLM service if API key is available
    /// Call this when API key is added in settings
    func switchToRealService() async {
        guard !isUsingRealAPI else { return }
        llmService = await LLMServiceFactory.shared.refreshService()
        logger.info("Refreshed LLM service")
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
        // Build context from portfolio
        let context = includePortfolioContext ? await buildContext() : ConversationContext(
            portfolioName: nil,
            positions: [],
            riskProfile: nil,
            targetAllocation: nil,
            totalValue: nil,
            totalCost: nil,
            totalProfitLoss: nil,
            profitLossPercentage: nil,
            portfolioCurrency: nil,
            expectedReturn: nil,
            maxDrawdown: nil,
            exchangeRates: nil
        )
        
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
        
        // Save history after each complete exchange
        saveChatHistory()
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
    
    private func buildContext() async -> ConversationContext {
        guard let portfolio = portfolio else {
            return ConversationContext(
                portfolioName: nil,
                positions: [],
                riskProfile: nil,
                targetAllocation: nil,
                totalValue: nil,
                totalCost: nil,
                totalProfitLoss: nil,
                profitLossPercentage: nil,
                portfolioCurrency: nil,
                expectedReturn: nil,
                maxDrawdown: nil,
                exchangeRates: nil
            )
        }
        
        let baseCurrency = portfolio.currency
        var exchangeRates: [String: Double]?
        
        do {
            exchangeRates = try await ExchangeRateProvider.shared.fetchRates(base: baseCurrency.code)
        } catch {
            logger.warning("Failed to fetch exchange rates: \(error)")
        }
        
        let positionSet = portfolio.positions as? Set<Position> ?? []
        let positions = positionSet.map { position -> ConversationContext.PositionSummary in
            let value = position.currentValue ?? 0
            let weight = portfolio.totalValue > 0 ? value / portfolio.totalValue : nil
            
            return ConversationContext.PositionSummary(
                symbol: position.symbol ?? "Unknown",
                name: position.name ?? "",
                shares: position.shares,
                currentPrice: position.currentPrice,
                currentValue: value,
                totalCost: position.totalCost,
                profitLoss: position.profitLoss,
                profitLossPercentage: position.profitLossPercentage,
                weight: weight,
                assetType: position.assetType.rawValue,
                market: position.market.rawValue,
                currency: position.currencyEnum.rawValue
            )
        }
        
        let totalValue: Double
        let totalCost: Double
        
        if let rates = exchangeRates {
            totalValue = portfolio.totalValueIn(currency: baseCurrency, rates: rates, positions: Array(positionSet))
            totalCost = portfolio.totalCostIn(currency: baseCurrency, rates: rates, positions: Array(positionSet))
        } else {
            totalValue = portfolio.totalValue
            totalCost = portfolio.totalCost
        }
        
        return ConversationContext(
            portfolioName: portfolio.name,
            positions: positions,
            riskProfile: portfolio.riskProfile.displayName,
            targetAllocation: portfolio.targetAllocation,
            totalValue: totalValue,
            totalCost: totalCost,
            totalProfitLoss: totalValue - totalCost,
            profitLossPercentage: totalCost > 0 ? (totalValue - totalCost) / totalCost : nil,
            portfolioCurrency: baseCurrency.rawValue,
            expectedReturn: portfolio.expectedReturn > 0 ? portfolio.expectedReturn : nil,
            maxDrawdown: portfolio.maxDrawdown > 0 ? portfolio.maxDrawdown : nil,
            exchangeRates: exchangeRates
        )
    }
}
