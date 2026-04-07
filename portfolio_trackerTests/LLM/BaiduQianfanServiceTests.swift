//
//  BaiduQianfanServiceTests.swift
//  portfolio_trackerTests
//
//  Unit tests for Baidu Qianfan LLM service
//

import XCTest
@testable import portfolio_tracker

@MainActor
final class BaiduQianfanServiceTests: TestCase {
    
    var service: BaiduQianfanService!
    
    override func setUp() async throws {
        try await super.setUp()
        service = createTestBaiduService()
    }
    
    override func tearDown() async throws {
        service = nil
        try await super.tearDown()
    }
    
    // MARK: - API Key Tests
    
    func testAPIKeyExists() async {
        // Save a test key
        try? await saveTestAPIKey("bce-test-key-12345", for: .baiduqianfan)
        
        let hasKey = await testAPIKeyManager.hasKey(for: .baiduqianfan)
        XCTAssertTrue(hasKey, "Test storage should have Baidu Qianfan key")
    }
    
    func testInvalidAPIKey() async throws {
        // Test with invalid key (in test storage, not real keychain!)
        let invalidKey = "bce-invalid-test-key-12345"
        try await testAPIKeyManager.saveKey(invalidKey, for: .baiduqianfan)
        
        let result = await service.validateAPIKey()
        
        // Invalid key should return invalid result
        XCTAssertFalse(result.isValid, "Invalid API key should not be valid")
        // No cleanup needed - test storage is discarded after test!
    }
    
    // MARK: - Context Tests
    
    func testContextBuilding() {
        let positions = [
            ConversationContext.PositionSummary(
                symbol: "AAPL",
                name: "Apple",
                shares: 100,
                currentPrice: 180,
                currentValue: 18000,
                totalCost: 15000,
                profitLoss: 3000,
                profitLossPercentage: 0.2,
                weight: 0.6,
                assetType: "stock",
                market: "US",
                currency: "USD"
            ),
            ConversationContext.PositionSummary(
                symbol: "MSFT",
                name: "Microsoft",
                shares: 50,
                currentPrice: 400,
                currentValue: 20000,
                totalCost: 18000,
                profitLoss: 2000,
                profitLossPercentage: 0.111,
                weight: 0.4,
                assetType: "stock",
                market: "US",
                currency: "USD"
            )
        ]
        
        let context = ConversationContext(
            portfolioName: "Test Portfolio",
            positions: positions,
            riskProfile: "moderate",
            targetAllocation: ["AAPL": 0.6, "MSFT": 0.4],
            totalValue: 38000,
            totalCost: 33000,
            totalProfitLoss: 5000,
            profitLossPercentage: 0.152,
            portfolioCurrency: "USD",
            expectedReturn: nil,
            maxDrawdown: nil,
            exchangeRates: nil
        )
        
        let contextString = SystemPrompts.buildContextString(context: context)
        
        XCTAssertTrue(contextString.contains("Test Portfolio"))
        XCTAssertTrue(contextString.contains("AAPL"))
        XCTAssertTrue(contextString.contains("MSFT"))
        XCTAssertTrue(contextString.contains("moderate"))
        XCTAssertTrue(contextString.contains("SECURITIES"))
        XCTAssertTrue(contextString.contains("Apple"))
        XCTAssertTrue(contextString.contains("Microsoft"))
        XCTAssertTrue(contextString.contains("60.0%"))
        
        print("✅ Context string:\n\(contextString)")
    }
    
    func testEmptyContext() {
        let context = createTestContext()
        
        let contextString = SystemPrompts.buildContextString(context: context)
        
        // Empty context should return empty string (no portfolio data)
        // The base prompt is separate and handled by the service
        XCTAssertTrue(contextString.isEmpty || !contextString.contains("Portfolio:"))
        
        // Verify base prompt is separate
        XCTAssertTrue(SystemPrompts.basePrompt.contains("investment advisor"))
        
        print("✅ Empty context string: '\(contextString)'")
    }
    
    func testContextWithCashPositions() {
        let positions = [
            ConversationContext.PositionSummary(
                symbol: "AAPL",
                name: "Apple",
                shares: 100,
                currentPrice: 180,
                currentValue: 18000,
                totalCost: 15000,
                profitLoss: 3000,
                profitLossPercentage: 0.2,
                weight: 0.36,
                assetType: "stock",
                market: "US",
                currency: "USD"
            ),
            ConversationContext.PositionSummary(
                symbol: "CASH-CNY",
                name: "现金",
                shares: 20000,
                currentPrice: 1,
                currentValue: 20000,
                totalCost: 20000,
                profitLoss: nil,
                profitLossPercentage: nil,
                weight: 0.4,
                assetType: "cash",
                market: "CN",
                currency: "CNY"
            ),
            ConversationContext.PositionSummary(
                symbol: "CASH-USD",
                name: "USD Cash",
                shares: 15000,
                currentPrice: 1,
                currentValue: 15000,
                totalCost: 15000,
                profitLoss: nil,
                profitLossPercentage: nil,
                weight: 0.24,
                assetType: "cash",
                market: "US",
                currency: "USD"
            )
        ]
        
        let context = ConversationContext(
            portfolioName: "Mixed Portfolio",
            positions: positions,
            riskProfile: "moderate",
            targetAllocation: ["AAPL": 0.6, "CASH-CNY": 0.2, "CASH-USD": 0.2],
            totalValue: 53000,
            totalCost: 50000,
            totalProfitLoss: 3000,
            profitLossPercentage: 0.06,
            portfolioCurrency: "CNY",
            expectedReturn: nil,
            maxDrawdown: nil,
            exchangeRates: ["CNY": 7.0, "USD": 1.0]
        )
        
        let contextString = SystemPrompts.buildContextString(context: context)
        
        // Verify securities section exists
        XCTAssertTrue(contextString.contains("SECURITIES"))
        XCTAssertTrue(contextString.contains("Apple"))
        XCTAssertTrue(contextString.contains("AAPL"))
        
        // Verify cash section exists
        XCTAssertTrue(contextString.contains("CASH"))
        XCTAssertTrue(contextString.contains("现金"))
        XCTAssertTrue(contextString.contains("USD Cash"))
        
        // Verify allocation analysis
        XCTAssertTrue(contextString.contains("TARGET ALLOCATION"))
        
        print("✅ Context with cash:\n\(contextString)")
    }
}
