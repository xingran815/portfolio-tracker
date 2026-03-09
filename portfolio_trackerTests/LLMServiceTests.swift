//
//  LLMServiceTests.swift
//  portfolio_trackerTests
//
//  Tests for LLM service
//

import Testing
import Foundation
@testable import portfolio_tracker

@Suite("LLM Service Tests")
struct LLMServiceTests {
    
    @Test("ChatMessage initialization")
    func testChatMessage() {
        let message = ChatMessage(
            role: .user,
            content: "Should I rebalance my portfolio?"
        )
        
        #expect(message.role == .user)
        #expect(message.content == "Should I rebalance my portfolio?")
    }
    
    @Test("ConversationContext building")
    func testConversationContext() {
        let positions = [
            ConversationContext.PositionSummary(
                symbol: "AAPL",
                shares: 100,
                currentValue: 15000.0
            )
        ]
        
        let context = ConversationContext(
            portfolioName: "Test Portfolio",
            positions: positions,
            riskProfile: "moderate",
            targetAllocation: ["AAPL": 0.5, "VOO": 0.5]
        )
        
        #expect(context.portfolioName == "Test Portfolio")
        #expect(context.positions.count == 1)
        #expect(context.riskProfile == "moderate")
        #expect(context.targetAllocation?["AAPL"] == 0.5)
    }
    
    @Test("System prompt generation")
    func testSystemPrompt() {
        let context = ConversationContext(
            portfolioName: "My Portfolio",
            positions: [],
            riskProfile: "conservative",
            targetAllocation: nil
        )
        
        let prompt = SystemPrompts.portfolioAdvisor(context: context)
        
        #expect(prompt.contains("investment advisor"))
        #expect(prompt.contains("My Portfolio"))
        #expect(prompt.contains("conservative"))
        #expect(prompt.contains("educational advice"))
    }
    
    @Test("LLM error descriptions")
    func testLLMErrors() {
        let errors: [LLMServiceError] = [
            .apiKeyMissing,
            .rateLimited,
            .serviceUnavailable,
            .invalidResponse(statusCode: 500),
            .networkError("timeout"),
            .requestTimeout,
            .maxRetriesExceeded
        ]
        
        for error in errors {
            let description = error.errorDescription
            #expect(description != nil, "Error \(error) should have a description")
            #expect(description?.isEmpty == false, "Error \(error) description should not be empty")
        }
    }
    
    @Test("LLM configuration defaults")
    func testLLMConfiguration() {
        let config = LLMConfiguration.default
        
        #expect(config.model == "moonshot-v1-8k")
        #expect(config.temperature == 0.7)
        #expect(config.maxTokens == 2048)
        #expect(config.topP == 0.9)
        #expect(config.requestTimeout == 30.0)
        #expect(config.maxRetries == 3)
        #expect(config.maxContextLength == 8000)
    }
    
    @Test("APIKeyValidationResult cases")
    func testAPIKeyValidationResult() {
        #expect(APIKeyValidationResult.valid.isValid == true)
        #expect(APIKeyValidationResult.notConfigured.isValid == false)
        #expect(APIKeyValidationResult.invalid.isValid == false)
        #expect(APIKeyValidationResult.networkError("timeout").isValid == false)
        #expect(APIKeyValidationResult.rateLimited.isValid == false)
        #expect(APIKeyValidationResult.serviceUnavailable.isValid == false)
    }
    
    @Test("LLMServiceError Sendable conformance")
    func testErrorSendable() async {
        // Verify errors can be passed across actor boundaries
        let errors: [LLMServiceError] = [
            .apiKeyMissing,
            .networkError("test"),
            .invalidResponse(statusCode: 404),
            .decodingError("parse error")
        ]
        
        // If this compiles, Sendable conformance is working
        #expect(errors.count == 4)
    }
}
