//
//  LLMServiceTests.swift
//  portfolio_trackerTests
//
//  Tests for LLM service
//

import XCTest
import Foundation
@testable import portfolio_tracker

final class LLMServiceTests: XCTestCase {
    
    // MARK: - ChatMessage Tests
    
    func testChatMessageInitialization() {
        let message = ChatMessage(
            role: .user,
            content: "Should I rebalance my portfolio?"
        )
        
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "Should I rebalance my portfolio?")
    }
    
    // MARK: - ConversationContext Tests
    
    func testConversationContextBuilding() {
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
        
        XCTAssertEqual(context.portfolioName, "Test Portfolio")
        XCTAssertEqual(context.positions.count, 1)
        XCTAssertEqual(context.riskProfile, "moderate")
        XCTAssertEqual(context.targetAllocation?["AAPL"], 0.5)
    }
    
    // MARK: - SystemPrompts Tests
    
    func testBasePromptContainsRequiredContent() {
        let prompt = SystemPrompts.basePrompt
        
        XCTAssertTrue(prompt.contains("investment advisor"))
        XCTAssertTrue(prompt.contains("portfolio management"))
        XCTAssertTrue(prompt.contains("rebalancing"))
    }
    
    func testContextStringBuilding() {
        let positions = [
            ConversationContext.PositionSummary(
                symbol: "AAPL",
                shares: 100,
                currentValue: 15000.0
            )
        ]
        
        let context = ConversationContext(
            portfolioName: "My Portfolio",
            positions: positions,
            riskProfile: "conservative",
            targetAllocation: ["AAPL": 0.6]
        )
        
        let contextString = SystemPrompts.buildContextString(context: context)
        
        XCTAssertTrue(contextString.contains("My Portfolio"))
        XCTAssertTrue(contextString.contains("conservative"))
        XCTAssertTrue(contextString.contains("AAPL"))
        XCTAssertTrue(contextString.contains("educational advice"))
    }
    
    func testContextStringWithNilValues() {
        let context = ConversationContext(
            portfolioName: nil,
            positions: [],
            riskProfile: nil,
            targetAllocation: nil
        )
        
        let contextString = SystemPrompts.buildContextString(context: context)
        
        XCTAssertTrue(contextString.contains("educational advice"))
    }
    
    // MARK: - LLM Error Tests
    
    func testLLMErrorDescriptions() {
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
            XCTAssertNotNil(description, "Error \(error) should have a description")
            XCTAssertFalse(description?.isEmpty ?? true, "Error \(error) description should not be empty")
        }
    }
    
    // MARK: - LLM Configuration Tests
    
    func testLLMConfigurationDefaults() {
        let config = LLMConfiguration.default
        
        XCTAssertEqual(config.model, "moonshot-v1-8k")
        XCTAssertEqual(config.temperature, 0.7, accuracy: 0.01)
        XCTAssertEqual(config.maxTokens, 2048)
        XCTAssertEqual(config.topP, 0.9, accuracy: 0.01)
        XCTAssertEqual(config.requestTimeout, 30.0, accuracy: 0.01)
        XCTAssertEqual(config.maxRetries, 3)
        XCTAssertEqual(config.maxContextLength, 8000)
    }
    
    // MARK: - API Key Validation Tests
    
    func testAPIKeyValidationResultCases() {
        XCTAssertTrue(APIKeyValidationResult.valid.isValid)
        XCTAssertFalse(APIKeyValidationResult.notConfigured.isValid)
        XCTAssertFalse(APIKeyValidationResult.invalid.isValid)
        XCTAssertFalse(APIKeyValidationResult.networkError("timeout").isValid)
        XCTAssertFalse(APIKeyValidationResult.rateLimited.isValid)
        XCTAssertFalse(APIKeyValidationResult.serviceUnavailable.isValid)
    }
    
    // MARK: - Sendable Conformance Test
    
    func testErrorSendableConformance() async {
        let errors: [LLMServiceError] = [
            .apiKeyMissing,
            .networkError("test"),
            .invalidResponse(statusCode: 404),
            .decodingError("parse error")
        ]
        
        XCTAssertEqual(errors.count, 4)
    }
}
