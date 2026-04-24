//
//  MockLLMService.swift
//  portfolio_tracker
//
//  Mock LLM service for testing without API key
//

import Foundation

/// Mock LLM service that returns canned responses
/// Use this for development when you don't have a valid API key
actor MockLLMService: LLMServiceProtocol {
    
    private var responseIndex = 0
    
    /// Whether this service supports web search
    nonisolated let supportsWebSearch: Bool = false

    /// Whether this service can autonomously decide when to search
    nonisolated let supportsAutonomousWebSearch: Bool = false

    func sendMessage(
        _ message: String,
        context: ConversationContext,
        history: [ChatMessage]
    ) -> AsyncStream<Result<String, LLMServiceError>> {
        AsyncStream { continuation in
            Task {
                // Simulate network delay
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                
                // Check for cancellation
                if Task.isCancelled {
                    continuation.yield(.failure(.cancelled))
                    continuation.finish()
                    return
                }
                
                let response = generateResponse(for: message, context: context)
                
                // Stream word by word
                let words = response.split(separator: " ")
                for (index, word) in words.enumerated() {
                    if Task.isCancelled {
                        continuation.yield(.failure(.cancelled))
                        continuation.finish()
                        return
                    }
                    
                    let chunk = index == 0 ? String(word) : " " + word
                    continuation.yield(.success(chunk))
                    
                    // Small delay between words
                    try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                }
                
                continuation.finish()
            }
        }
    }
    
    func validateAPIKey() async -> APIKeyValidationResult {
        return .valid
    }
    
    func clearHistory() {
        // Mock service doesn't maintain persistent history
    }
    
    // MARK: - Response Generation
    
    private func generateResponse(for message: String, context: ConversationContext) -> String {
        let lowerMessage = message.lowercased()
        
        // Portfolio-specific responses
        if lowerMessage.contains("rebalance") {
            return generateRebalanceAdvice(context: context)
        } else if lowerMessage.contains("risk") {
            return generateRiskAdvice(context: context)
        } else if lowerMessage.contains("allocation") || lowerMessage.contains("分配") {
            return generateAllocationAdvice(context: context)
        } else if context.positions.isEmpty {
            return "I see you don't have any positions in your portfolio yet. You can add stocks by importing from a Markdown file or adding them manually. Would you like help with that?"
        } else {
            return generateGeneralAdvice(context: context)
        }
    }
    
    private func generateRebalanceAdvice(context: ConversationContext) -> String {
        let portfolioName = context.portfolioName ?? "your portfolio"
        
        return """
        Based on your current holdings in \(portfolioName), here's my rebalancing recommendation:
        
        **Current Status:**
        Your portfolio appears to be within acceptable drift limits. However, I recommend reviewing your allocations quarterly.
        
        **Suggested Actions:**
        1. Consider taking profits on positions that have grown beyond target allocation
        2. Add to underweight positions during market dips
        3. Review tax implications before making changes
        
        **Note:** This is educational advice. Please consult with a licensed financial advisor before making investment decisions.
        """
    }
    
    private func generateRiskAdvice(context: ConversationContext) -> String {
        let riskProfile = context.riskProfile ?? "moderate"
        
        return """
        Your current risk profile is set to **\(riskProfile)**.
        
        For a \(riskProfile) investor, I typically recommend:
        - Diversified portfolio across multiple sectors
        - Mix of growth and value stocks
        - Regular rebalancing to maintain target allocation
        - Emergency fund separate from investments
        
        Would you like me to analyze your current positions against this profile?
        """
    }
    
    private func generateAllocationAdvice(context: ConversationContext) -> String {
        guard let allocation = context.targetAllocation, !allocation.isEmpty else {
            return "I don't see a target allocation set for your portfolio. Would you like help setting one up based on your risk profile and investment goals?"
        }
        
        var response = "Your target allocation is:\n\n"
        for (symbol, percentage) in allocation.sorted(by: { $0.value > $1.value }) {
            response += "- \(symbol): \(Int(percentage * 100))%\n"
        }
        
        response += "\nThis looks like a well-diversified portfolio. I can help you track how your actual holdings compare to these targets."
        
        return response
    }
    
    private func generateGeneralAdvice(context: ConversationContext) -> String {
        let responses = [
            "I'm here to help with your portfolio management questions. You can ask me about rebalancing, risk assessment, or general investment strategy.",
            
            "Based on your portfolio data, everything looks on track. Remember to review your investments regularly and adjust as your financial goals change.",
            
            "Good question! For personalized advice, I'd need to know more about your investment timeline and risk tolerance. Could you tell me more?",
            
            "Portfolio management is a long-term journey. Stay diversified, keep costs low, and stick to your plan during market volatility."
        ]
        
        // Use round-robin instead of random for predictable testing
        let index = responseIndex % responses.count
        responseIndex += 1
        return responses[index]
    }
}
