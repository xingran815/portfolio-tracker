//
//  BaiduQianfanServiceIntegrationTests.swift
//  portfolio_trackerTests
//
//  Integration tests for Baidu Qianfan LLM service (requires real API key)
//

import XCTest
@testable import portfolio_tracker

/// Integration tests that require real Baidu Qianfan API key
/// These tests will be skipped if API key is not configured
@MainActor
final class BaiduQianfanServiceIntegrationTests: IntegrationTestCase {
    
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
    
    func testAPIKeyExists() async throws {
        // This test requires the user to add Baidu Qianfan API key to keychain first
        let apiKey = try await skipIfMissingKey(.baiduqianfan)
        print("✅ Baidu Qianfan API key is configured (length: \(apiKey.count))")
    }
    
    func testAPIKeyValidation() async throws {
        // Skip if API key not configured
        try await skipIfMissingKey(.baiduqianfan)
        
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
        try await skipIfMissingKey(.baiduqianfan)
        
        let context = createTestContext(portfolioName: "Test Portfolio")
        
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
        try await skipIfMissingKey(.baiduqianfan)
        
        let positions = [
            createTestPosition(symbol: "AAPL", shares: 100, price: 150),
            createTestPosition(symbol: "MSFT", shares: 50, price: 300)
        ]
        
        let context = ConversationContext(
            portfolioName: "Tech Portfolio",
            positions: positions,
            riskProfile: "moderate",
            targetAllocation: ["AAPL": 0.6, "MSFT": 0.4],
            totalValue: 30000,
            totalCost: 25000,
            totalProfitLoss: 5000,
            profitLossPercentage: 0.2,
            portfolioCurrency: "USD",
            expectedReturn: nil,
            maxDrawdown: nil,
            exchangeRates: nil
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
        try await skipIfMissingKey(.baiduqianfan)
        
        let kimiService = BaiduQianfanService(model: .kimi_k2_5)
        
        let stream = await kimiService.sendMessage(
            "Say hello in one word",
            context: createTestContext(),
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
        try await skipIfMissingKey(.baiduqianfan)
        
        let glmService = BaiduQianfanService(model: .glm5)
        
        let stream = await glmService.sendMessage(
            "Say hello in one word",
            context: createTestContext(),
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
        try await skipIfMissingKey(.baiduqianfan)
        
        let minimaxService = BaiduQianfanService(model: .minimax_m2_5)
        
        let stream = await minimaxService.sendMessage(
            "Say hello in one word",
            context: createTestContext(),
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
        try await skipIfMissingKey(.baiduqianfan)
        
        let models: [BaiduQianfanService.Model] = [.kimi_k2_5, .glm5, .minimax_m2_5]
        
        for model in models {
            let modelService = BaiduQianfanService(model: model)
            
            let stream = await modelService.sendMessage(
                "Say hello",
                context: createTestContext(),
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
}
