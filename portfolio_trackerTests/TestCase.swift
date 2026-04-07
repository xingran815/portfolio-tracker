//
//  TestCase.swift
//  portfolio_trackerTests
//
//  Base test class with test API key storage
//

import XCTest
@testable import portfolio_tracker

/// Base test class that provides isolated test storage
/// Tests that use API keys should inherit from this class
@MainActor
class TestCase: XCTestCase {
    
    /// Test storage instance (in-memory, isolated per test)
    var testStorage: InMemoryStorage!
    
    /// APIKeyManager with test storage
    var testAPIKeyManager: APIKeyManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create fresh test storage for each test
        testStorage = InMemoryStorage()
        testAPIKeyManager = APIKeyManager(storage: testStorage)
    }
    
    override func tearDown() async throws {
        // Clear all keys (optional cleanup)
        await testStorage.clearAll()
        
        testStorage = nil
        testAPIKeyManager = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Saves a test API key
    func saveTestAPIKey(_ key: String, for service: APIService) async throws {
        try await testAPIKeyManager.saveKey(key, for: service)
    }
    
    /// Creates a test BaiduQianfanService with test storage
    func createTestBaiduService(model: BaiduQianfanService.Model = .kimi_k2_5) -> BaiduQianfanService {
        return BaiduQianfanService(apiKeyManager: testAPIKeyManager, model: model)
    }
    
    /// Creates a test KimiService with test storage
    func createTestKimiService() -> KimiService {
        return KimiService(apiKeyManager: testAPIKeyManager)
    }
    
    /// Creates a test TavilyService with test storage
    func createTestTavilyService() -> TavilyService {
        return TavilyService(apiKeyManager: testAPIKeyManager)
    }
    
    /// Creates a test conversation context with optional portfolio data
    func createTestContext(
        portfolioName: String? = nil,
        positions: [ConversationContext.PositionSummary] = []
    ) -> ConversationContext {
        ConversationContext(
            portfolioName: portfolioName,
            positions: positions,
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
    
    /// Creates a test position
    func createTestPosition(
        symbol: String = "AAPL",
        shares: Double = 100,
        price: Double = 150.0
    ) -> ConversationContext.PositionSummary {
        ConversationContext.PositionSummary(
            symbol: symbol,
            name: symbol,
            shares: shares,
            currentPrice: price,
            currentValue: shares * price,
            totalCost: shares * price * 0.8,
            profitLoss: shares * price * 0.2,
            profitLossPercentage: 0.25,
            weight: 1.0,
            assetType: "stock",
            market: "US",
            currency: "USD"
        )
    }
    
    /// Assert that an async throws throws a specific error
    func assertThrows<E: Error & Equatable>(
        _ error: E,
        _ expression: () async throws -> Void,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected to throw \(error), but succeeded", file: file, line: line)
        } catch let thrownError as E {
            XCTAssertEqual(thrownError, error, message, file: file, line: line)
        } catch {
            XCTFail("Expected \(error), but threw \(error)", file: file, line: line)
        }
    }
}
