//
//  TavilyServiceTests.swift
//  portfolio_trackerTests
//
//  Unit tests for Tavily web search service
//

import XCTest
@testable import portfolio_tracker

@MainActor
final class TavilyServiceTests: TestCase {
    
    var service: TavilyService!
    
    override func setUp() async throws {
        try await super.setUp()
        service = createTestTavilyService()
    }
    
    override func tearDown() async throws {
        service = nil
        try await super.tearDown()
    }
    
    // MARK: - API Key Tests
    
    func testAPIKeyExists() async {
        // Save a test key
        try? await saveTestAPIKey("tvly-test-key-12345", for: .tavily)
        
        let hasKey = await testAPIKeyManager.hasKey(for: .tavily)
        XCTAssertTrue(hasKey, "Test storage should have Tavily key")
    }
    
    func testSearchWithoutAPIKey() async throws {
        // Don't save any key - test error handling
        do {
            _ = try await service.search(query: "test", options: .default)
            XCTFail("Should throw error when API key is missing")
        } catch let error as TavilyError {
            if case .apiKeyNotConfigured = error {
                XCTAssertTrue(true, "Correctly throws apiKeyNotConfigured error")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Model Tests
    
    func testSearchOptionsDefault() {
        let options = TavilySearchOptions.default
        
        XCTAssertEqual(options.maxResults, 5)
        XCTAssertEqual(options.searchDepth, "basic")
        XCTAssertTrue(options.includeAnswer)
        XCTAssertEqual(options.topic, "finance")
        XCTAssertNil(options.timeRange)
    }
    
    func testSearchOptionsNews() {
        let options = TavilySearchOptions.news
        
        XCTAssertEqual(options.maxResults, 5)
        XCTAssertEqual(options.topic, "news")
        XCTAssertEqual(options.timeRange, "week")
    }
    
    func testSearchResultHasResults() {
        let resultWithResults = TavilySearchResult(
            query: "test",
            answer: nil,
            results: [
                TavilySearchResultItem(
                    title: "Test",
                    url: "https://example.com",
                    content: "Content",
                    score: 0.9,
                    publishedDate: nil
                )
            ],
            responseTime: 1.0
        )
        XCTAssertTrue(resultWithResults.hasResults)
        
        let resultEmpty = TavilySearchResult(
            query: "test",
            answer: nil,
            results: [],
            responseTime: 1.0
        )
        XCTAssertFalse(resultEmpty.hasResults)
    }
}
