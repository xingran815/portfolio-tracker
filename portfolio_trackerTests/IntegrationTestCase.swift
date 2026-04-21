//
//  IntegrationTestCase.swift
//  portfolio_trackerTests
//
//  Base class for integration tests that use real API keys
//

import XCTest
@testable import portfolio_tracker

/// Base class for integration tests requiring real API keys
/// These tests are SLOW and require actual keychain/API access
/// - Note: Tests will be skipped if required keys aren't configured
class IntegrationTestCase: XCTestCase {
    
    /// Check if a specific API key is configured
    /// Returns the key if available, nil otherwise
    func requireAPIKey(_ service: APIService) async throws -> String? {
        do {
            let key = try await APIKeyManager.shared.getKey(for: service)
            return key
        } catch {
            return nil
        }
    }
    
    /// Skip test if API key not configured
    func skipIfMissingKey(_ service: APIService) async throws -> String {
        guard let key = try await requireAPIKey(service) else {
            throw XCTSkip("\(service.displayName) API key not configured - skipping integration test")
        }
        return key
    }
    
    /// Skip test if any of the specified API keys are not configured
    func skipIfMissingKeys(_ services: APIService...) async throws {
        for service in services {
            _ = try await skipIfMissingKey(service)
        }
    }
    
    /// Check if a specific API key is configured (non-throwing version)
    func hasAPIKey(_ service: APIService) async -> Bool {
        do {
            _ = try await APIKeyManager.shared.getKey(for: service)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Test Data Helpers
    
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
}
