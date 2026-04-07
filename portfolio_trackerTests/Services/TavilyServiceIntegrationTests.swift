//
//  TavilyServiceIntegrationTests.swift
//  portfolio_trackerTests
//
//  Integration tests for Tavily web search service (requires real API key)
//

import XCTest
@testable import portfolio_tracker

/// Integration tests that require real Tavily API key
/// These tests will be skipped if API key is not configured
@MainActor
final class TavilyServiceIntegrationTests: IntegrationTestCase {
    
    // MARK: - API Key Validation Tests
    
    func testAPIKeyValidation() async throws {
        // Skip if API key not configured
        let apiKey = try await skipIfMissingKey(.tavily)
        
        let result = await TavilyService.shared.validateAPIKey()
        
        switch result {
        case .valid:
            XCTAssertTrue(true, "API key is valid")
        case .notConfigured:
            XCTFail("API key should be configured - already checked")
        case .invalid:
            XCTFail("API key is invalid - check the key in keychain")
        case .rateLimited:
            XCTAssertTrue(true, "API key is valid but rate limited")
        case .networkError(let message):
            XCTFail("Network error: \(message)")
        case .serviceUnavailable:
            XCTFail("Service unavailable")
        }
    }
    
    // MARK: - Search Tests
    
    func testBasicSearch() async throws {
        // Skip if API key not configured
        try await skipIfMissingKey(.tavily)
        
        let result = try await TavilyService.shared.search(
            query: "Apple stock price",
            options: .default
        )
        
        XCTAssertFalse(result.results.isEmpty, "Should return search results")
        XCTAssertFalse(result.query.isEmpty, "Query should be preserved")
        
        print("✅ Search returned \(result.results.count) results in \(result.responseTime)s")
    }
    
    func testFinanceSearch() async throws {
        // Skip if API key not configured
        try await skipIfMissingKey(.tavily)
        
        let result = try await TavilyService.shared.search(
            query: "NVDA NVIDIA stock price today",
            options: TavilySearchOptions(
                maxResults: 5,
                searchDepth: "basic",
                includeAnswer: true,
                topic: "finance",
                timeRange: nil
            )
        )
        
        XCTAssertFalse(result.results.isEmpty, "Should return finance results")
        
        if let answer = result.answer {
            XCTAssertFalse(answer.isEmpty, "AI answer should not be empty")
            print("✅ AI Answer: \(answer)")
        }
        
        for (index, item) in result.results.enumerated() {
            print("  \(index + 1). \(item.title) (score: \(item.score))")
        }
    }
    
    func testNewsSearch() async throws {
        // Skip if API key not configured
        try await skipIfMissingKey(.tavily)
        
        do {
            let result = try await TavilyService.shared.search(
                query: "Federal Reserve interest rate",
                options: .news
            )
            
            XCTAssertFalse(result.results.isEmpty, "Should return news results")
            
            print("✅ News search returned \(result.results.count) results")
        } catch let error as TavilyError {
            // Handle rate limiting gracefully
            if case .rateLimited = error {
                throw XCTSkip("Tavily API rate limited - try again later")
            }
            throw error
        }
    }
    
    func testSearchResultFormat() async throws {
        // Skip if API key not configured
        try await skipIfMissingKey(.tavily)
        
        do {
            let result = try await TavilyService.shared.search(
                query: "Tesla TSLA",
                options: TavilySearchOptions(
                    maxResults: 3,
                    searchDepth: "basic",
                    includeAnswer: false,
                    topic: "finance",
                    timeRange: nil
                )
            )
            
            for item in result.results {
                XCTAssertFalse(item.title.isEmpty, "Title should not be empty")
                XCTAssertFalse(item.url.isEmpty, "URL should not be empty")
                XCTAssertFalse(item.content.isEmpty, "Content should not be empty")
                XCTAssertGreaterThan(item.score, 0, "Score should be positive")
                
                // Verify URL is valid
                XCTAssertNotNil(URL(string: item.url), "URL should be valid")
            }
        } catch let error as TavilyError {
            // Handle rate limiting gracefully
            if case .rateLimited = error {
                throw XCTSkip("Tavily API rate limited - try again later")
            }
            throw error
        }
    }
}
