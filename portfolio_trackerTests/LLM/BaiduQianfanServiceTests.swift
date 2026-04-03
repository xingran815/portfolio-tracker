//
//  BaiduQianfanServiceTests.swift
//  portfolio_trackerTests
//
//  Tests for Baidu Qianfan LLM service
//

import XCTest
@testable import portfolio_tracker

@MainActor
final class BaiduQianfanServiceTests: XCTestCase {
    
    var service: BaiduQianfanService!
    
    override func setUp() async throws {
        try await super.setUp()
        service = BaiduQianfanService()
    }
    
    override func tearDown() async throws {
        service = nil
        try await super.tearDown()
    }
    
    // MARK: - API Key Tests
    
    func testAPIKeyExists() async {
        // This test requires the user to add Baidu Qianfan API key to keychain first
        // Use: security add-generic-password -a "com.portfolio_tracker.baiduqianfan" -s "com.portfolio_tracker.apikeys" -w "YOUR_KEY"
        let hasKey = await APIKeyManager.shared.hasKey(for: .baiduqianfan)
        XCTAssertTrue(hasKey, "Baidu Qianfan API key should exist in keychain. Add it using: security add-generic-password -a \"com.portfolio_tracker.baiduqianfan\" -s \"com.portfolio_tracker.apikeys\" -w \"YOUR_KEY\"")
    }
    
    func testAPIKeyValidation() async {
        let result = await service.validateAPIKey()
        
        switch result {
        case .valid:
            XCTAssertTrue(true, "API key is valid")
        case .notConfigured:
            XCTFail("API key is missing - add it to keychain first")
        case .invalid:
            XCTFail("API key is invalid")
        case .rateLimited:
            XCTFail("API is rate limited")
        case .networkError(let message):
            XCTFail("Network error: \(message)")
        case .serviceUnavailable:
            XCTFail("Service unavailable")
        }
    }
    
    // MARK: - Message Tests
    
    func testSendMessageBasic() async throws {
        // Skip if API key not configured
        guard await APIKeyManager.shared.hasKey(for: .baiduqianfan) else {
            throw XCTSkip("Baidu Qianfan API key not configured")
        }
        
        let context = ConversationContext(
            portfolioName: "Test Portfolio",
            positions: [],
            riskProfile: nil,
            targetAllocation: nil
        )
        
        let stream = await service.sendMessage(
            "Hello, this is a test",
            context: context,
            history: []
        )
        
        var receivedChunks = 0
        var fullResponse = ""
        
        for await result in stream {
            switch result {
            case .success(let chunk):
                receivedChunks += 1
                fullResponse += chunk
            case .failure(let error):
                XCTFail("Error receiving stream: \(error)")
            }
        }
        
        XCTAssertGreaterThan(receivedChunks, 0, "Should receive at least one chunk")
        XCTAssertFalse(fullResponse.isEmpty, "Response should not be empty")
        
        print("✅ Received \(receivedChunks) chunks")
        print("✅ Response: \(fullResponse)")
    }
    
    func testSendMessageWithPortfolioContext() async throws {
        // Skip if API key not configured
        guard await APIKeyManager.shared.hasKey(for: .baiduqianfan) else {
            throw XCTSkip("Baidu Qianfan API key not configured")
        }
        
        let positions = [
            ConversationContext.PositionSummary(symbol: "AAPL", shares: 100, currentValue: 15000),
            ConversationContext.PositionSummary(symbol: "MSFT", shares: 50, currentValue: 15000)
        ]
        
        let context = ConversationContext(
            portfolioName: "Tech Portfolio",
            positions: positions,
            riskProfile: "moderate",
            targetAllocation: ["AAPL": 0.6, "MSFT": 0.4]
        )
        
        let stream = await service.sendMessage(
            "What is my portfolio allocation?",
            context: context,
            history: []
        )
        
        var fullResponse = ""
        for await result in stream {
            if case .success(let chunk) = result {
                fullResponse += chunk
            }
        }
        
        XCTAssertFalse(fullResponse.isEmpty)
        // Check that response mentions portfolio context
        let lowercased = fullResponse.lowercased()
        XCTAssertTrue(
            lowercased.contains("aapl") || lowercased.contains("apple") || lowercased.contains("portfolio"),
            "Response should mention portfolio or positions"
        )
        
        print("✅ Response with context: \(fullResponse)")
    }
    
    // MARK: - Model Tests
    
    func testModelKimiK25() async throws {
        // Skip if API key not configured
        guard await APIKeyManager.shared.hasKey(for: .baiduqianfan) else {
            throw XCTSkip("Baidu Qianfan API key not configured")
        }
        
        let kimiService = BaiduQianfanService(model: .kimi_k2_5)
        
        let stream = await kimiService.sendMessage(
            "Say hello in one word",
            context: ConversationContext(portfolioName: nil, positions: [], riskProfile: nil, targetAllocation: nil),
            history: []
        )
        
        var received = false
        var response = ""
        for await result in stream {
            if case .success(let chunk) = result {
                received = true
                response += chunk
            }
        }
        
        XCTAssertTrue(received, "Kimi-K2.5 should respond")
        print("✅ Kimi-K2.5: \(response)")
    }
    
    func testModelGLM5() async throws {
        // Skip if API key not configured
        guard await APIKeyManager.shared.hasKey(for: .baiduqianfan) else {
            throw XCTSkip("Baidu Qianfan API key not configured")
        }
        
        let glmService = BaiduQianfanService(model: .glm5)
        
        let stream = await glmService.sendMessage(
            "Say hello in one word",
            context: ConversationContext(portfolioName: nil, positions: [], riskProfile: nil, targetAllocation: nil),
            history: []
        )
        
        var received = false
        var response = ""
        for await result in stream {
            if case .success(let chunk) = result {
                received = true
                response += chunk
            }
        }
        
        XCTAssertTrue(received, "GLM-5 should respond")
        print("✅ GLM-5: \(response)")
    }
    
    func testModelMinimaxM25() async throws {
        // Skip if API key not configured
        guard await APIKeyManager.shared.hasKey(for: .baiduqianfan) else {
            throw XCTSkip("Baidu Qianfan API key not configured")
        }
        
        let minimaxService = BaiduQianfanService(model: .minimax_m2_5)
        
        let stream = await minimaxService.sendMessage(
            "Say hello in one word",
            context: ConversationContext(portfolioName: nil, positions: [], riskProfile: nil, targetAllocation: nil),
            history: []
        )
        
        var received = false
        var response = ""
        for await result in stream {
            if case .success(let chunk) = result {
                received = true
                response += chunk
            }
        }
        
        XCTAssertTrue(received, "MiniMax-M2.5 should respond")
        print("✅ MiniMax-M2.5: \(response)")
    }
    
    func testAllModelsRespond() async throws {
        // Skip if API key not configured
        guard await APIKeyManager.shared.hasKey(for: .baiduqianfan) else {
            throw XCTSkip("Baidu Qianfan API key not configured")
        }
        
        let models: [BaiduQianfanService.Model] = [.kimi_k2_5, .glm5, .minimax_m2_5]
        
        for model in models {
            let modelService = BaiduQianfanService(model: model)
            
            let stream = await modelService.sendMessage(
                "Say hello",
                context: ConversationContext(portfolioName: nil, positions: [], riskProfile: nil, targetAllocation: nil),
                history: []
            )
            
            var received = false
            for await result in stream {
                if case .success(_) = result {
                    received = true
                    break // We just need to know it works
                }
            }
            
            XCTAssertTrue(received, "\(model.displayName) should respond")
            print("✅ \(model.displayName) responded successfully")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidAPIKey() async {
        // Save current key
        let hasOriginalKey = await APIKeyManager.shared.hasKey(for: .baiduqianfan)
        var originalKey: String?
        if hasOriginalKey {
            originalKey = try? await APIKeyManager.shared.getKey(for: .baiduqianfan)
        }
        
        // Test with invalid key
        let invalidKey = "bce-invalid-test-key-12345"
        try? await APIKeyManager.shared.saveKey(invalidKey, for: .baiduqianfan)
        
        let result = await service.validateAPIKey()
        
        // Restore original key
        if let key = originalKey {
            try? await APIKeyManager.shared.saveKey(key, for: .baiduqianfan)
        } else {
            try? await APIKeyManager.shared.deleteKey(for: .baiduqianfan)
        }
        
        // Invalid key should return invalid result
        XCTAssertFalse(result.isValid, "Invalid API key should not be valid")
    }
    
    // MARK: - Context Tests
    
    func testContextBuilding() {
        let positions = [
            ConversationContext.PositionSummary(symbol: "AAPL", shares: 100, currentValue: 15000),
            ConversationContext.PositionSummary(symbol: "MSFT", shares: 50, currentValue: 15000)
        ]
        
        let context = ConversationContext(
            portfolioName: "Test Portfolio",
            positions: positions,
            riskProfile: "moderate",
            targetAllocation: ["AAPL": 0.6, "MSFT": 0.4]
        )
        
        let contextString = SystemPrompts.buildContextString(context: context)
        
        XCTAssertTrue(contextString.contains("Test Portfolio"))
        XCTAssertTrue(contextString.contains("AAPL"))
        XCTAssertTrue(contextString.contains("MSFT"))
        XCTAssertTrue(contextString.contains("moderate"))
        XCTAssertTrue(contextString.contains("60.0%"))
        
        print("✅ Context string:\n\(contextString)")
    }
    
    func testEmptyContext() {
        let context = ConversationContext(
            portfolioName: nil,
            positions: [],
            riskProfile: nil,
            targetAllocation: nil
        )
        
        let contextString = SystemPrompts.buildContextString(context: context)
        
        // Empty context should return empty string (no portfolio data)
        // The base prompt is separate and handled by the service
        XCTAssertTrue(contextString.isEmpty || !contextString.contains("Portfolio:"))
        
        // Verify base prompt is separate
        XCTAssertTrue(SystemPrompts.basePrompt.contains("investment advisor"))
        
        print("✅ Empty context string: '\(contextString)'")
    }
}
