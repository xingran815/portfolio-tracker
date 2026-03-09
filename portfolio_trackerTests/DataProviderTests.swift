//
//  DataProviderTests.swift
//  portfolio_trackerTests
//
//  Tests for DataProvider implementations
//

import Testing
import Foundation
@testable import portfolio_tracker

/// Mock URLSession for testing network requests
final class MockURLSession: URLSession {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    
    override func data(from url: URL) async throws -> (Data, URLResponse) {
        if let error = mockError {
            throw error
        }
        
        guard let data = mockData, let response = mockResponse else {
            throw URLError(.badServerResponse)
        }
        
        return (data, response)
    }
}

@Suite("AlphaVantageProvider Tests")
struct AlphaVantageProviderTests {
    
    @Test("Quote struct formatted properties")
    func testQuoteFormattedProperties() {
        let quote = Quote(
            symbol: "AAPL",
            price: 153.50,
            change: 1.50,
            changePercent: 0.9868,
            volume: 50_000_000,
            lastUpdated: Date(),
            currency: "USD"
        )
        
        #expect(quote.formattedPrice == "153.50")
        #expect(quote.formattedChange.contains("+1.50"))
    }
}

@Suite("RateLimiter Tests")
struct RateLimiterTests {
    
    @Test("Rate limiter enforces max requests")
    func testRateLimiter() async {
        // Given
        let limiter = RateLimiter(maxRequests: 2, perSeconds: 1)
        
        // When - Record 2 requests
        await limiter.recordRequest()
        await limiter.recordRequest()
        
        // Then - Should have 0 remaining
        let remaining = await limiter.remainingRequests
        #expect(remaining == 0)
    }
}

@Suite("QuoteCache Tests")
struct QuoteCacheTests {
    
    @Test("Cache stores and retrieves quotes")
    func testCacheStoreAndRetrieve() async {
        // Given
        let cache = QuoteCache()
        let quote = Quote(
            symbol: "AAPL",
            price: 150.0,
            change: 1.0,
            changePercent: 0.5,
            volume: 1000,
            lastUpdated: Date(),
            currency: "USD"
        )
        
        // When
        await cache.set(symbol: "AAPL", quote: quote)
        let retrieved = await cache.get(symbol: "AAPL")
        
        // Then
        #expect(retrieved != nil)
        #expect(retrieved?.price == 150.0)
    }
}
