//
//  WebSearchIntegrationTests.swift
//  portfolio_trackerTests
//
//  Integration tests for web search with LLM services (requires real API keys)
//

import XCTest
@testable import portfolio_tracker

/// Integration tests that require real API keys
/// These tests will be skipped if API keys are not configured
@MainActor
final class WebSearchIntegrationTests: IntegrationTestCase {
    
    var baiduService: BaiduQianfanService!
    
    override func setUp() async throws {
        try await super.setUp()
        baiduService = BaiduQianfanService()
    }
    
    override func tearDown() async throws {
        baiduService = nil
        try await super.tearDown()
    }
    
    // MARK: - Web Search Availability Tests
    
    func testBaiduQianfanSupportsWebSearch() {
        let service = BaiduQianfanService()
        XCTAssertTrue(service.supportsWebSearch, "BaiduQianfanService should support web search")
    }
    
    func testKimiSupportsWebSearch() {
        let service = KimiService()
        XCTAssertTrue(service.supportsWebSearch, "KimiService should support web search")
    }
    
    func testMockServiceDoesNotSupportWebSearch() {
        let mockService = MockLLMService()
        XCTAssertFalse(mockService.supportsWebSearch, "MockLLMService should not support web search")
    }
    
    // MARK: - Tavily Configuration Tests
    
    func testTavilyConfigurationRequired() async {
        // Tavily key should be configured for Baidu Qianfan web search
        let hasTavilyKey = await hasAPIKey(.tavily)
        
        if hasTavilyKey {
            print("✅ Tavily API key is configured")
        } else {
            print("⚠️ Tavily API key is not configured - web search will not work with Baidu Qianfan")
        }
    }
    
    // MARK: - Web Search Integration Tests
    
    func testBaiduQianfanWithWebSearch() async throws {
        // Skip if API keys not configured
        try await skipIfMissingKeys(.baiduqianfan, .tavily)
        
        let context = createTestContext()
        
        let stream = await baiduService.sendMessage(
            "What is the current price of Apple stock?",
            context: context,
            history: [],
            enableWebSearch: true
        )
        
        var fullResponse = ""
        var receivedChunks = 0
        
        for await result in stream {
            switch result {
            case .success(let chunk):
                fullResponse += chunk
                receivedChunks += 1
            case .failure(let error):
                XCTFail("Error receiving stream: \(error)")
            }
        }
        
        XCTAssertGreaterThan(receivedChunks, 0, "Should receive response chunks")
        XCTAssertFalse(fullResponse.isEmpty, "Response should not be empty")
        
        // Response should contain some indication of web search results
        let lowercased = fullResponse.lowercased()
        let hasPrice = lowercased.contains("$") || lowercased.contains("price")
        let hasCitation = lowercased.contains("[1]") || lowercased.contains("[2]")
        
        XCTAssertTrue(hasPrice || hasCitation, "Response should contain price info or citations from web search")
        
        print("✅ Response with web search: \(fullResponse)")
    }
    
    func testBaiduQianfanWithoutWebSearch() async throws {
        // Skip if API key not configured
        try await skipIfMissingKey(.baiduqianfan)
        
        let context = createTestContext()
        
        let stream = await baiduService.sendMessage(
            "Say hello",
            context: context,
            history: [],
            enableWebSearch: false
        )
        
        var fullResponse = ""
        
        for await result in stream {
            if case .success(let chunk) = result {
                fullResponse += chunk
            }
        }
        
        XCTAssertFalse(fullResponse.isEmpty, "Response should not be empty")
        
        print("✅ Response without web search: \(fullResponse)")
    }
    
    // MARK: - System Prompt Context Tests
    
    func testWebSearchContextFormatting() {
        let searchResult = TavilySearchResult(
            query: "Apple stock price",
            answer: "Apple stock is trading at $180.",
            results: [
                TavilySearchResultItem(
                    title: "Apple Inc Stock Price",
                    url: "https://finance.yahoo.com/quote/AAPL",
                    content: "Apple Inc. stock price is $180.50 as of today.",
                    score: 0.95,
                    publishedDate: nil
                ),
                TavilySearchResultItem(
                    title: "AAPL Stock",
                    url: "https://www.marketwatch.com/aapl",
                    content: "Current price: $180.50",
                    score: 0.88,
                    publishedDate: nil
                )
            ],
            responseTime: 2.5
        )
        
        let contextString = searchResult.toSystemPromptContext()
        
        XCTAssertTrue(contextString.contains("WEB SEARCH RESULTS"))
        XCTAssertTrue(contextString.contains("Apple stock price"))
        XCTAssertTrue(contextString.contains("Apple Inc Stock Price"))
        XCTAssertTrue(contextString.contains("$180.50"))
        XCTAssertTrue(contextString.contains("https://finance.yahoo.com/quote/AAPL"))
        XCTAssertTrue(contextString.contains("INSTRUCTIONS"))
        XCTAssertTrue(contextString.contains("[1]"))
        XCTAssertTrue(contextString.contains("[2]"))
        
        print("✅ Formatted context:\n\(contextString)")
    }
    
    func testWebSearchContextWithoutAnswer() {
        let searchResult = TavilySearchResult(
            query: "Test query",
            answer: nil,
            results: [
                TavilySearchResultItem(
                    title: "Test Title",
                    url: "https://example.com",
                    content: "Test content",
                    score: 0.9,
                    publishedDate: nil
                )
            ],
            responseTime: 1.0
        )
        
        let contextString = searchResult.toSystemPromptContext()
        
        XCTAssertTrue(contextString.contains("WEB SEARCH RESULTS"))
        XCTAssertTrue(contextString.contains("Test query"))
        XCTAssertFalse(contextString.contains("Summary:"))
        
        print("✅ Context without answer:\n\(contextString)")
    }
    
    // MARK: - Error Handling Tests
    
    func testWebSearchGracefulDegradation() async throws {
        // Skip if Baidu Qianfan API key not configured
        try await skipIfMissingKey(.baiduqianfan)
        
        // Test that LLM still works even when web search fails (no Tavily key)
        let hasTavilyKey = await hasAPIKey(.tavily)
        
        if !hasTavilyKey {
            let context = createTestContext()
            
            // Even with web search enabled, should still work (just skip search)
            let stream = await baiduService.sendMessage(
                "Hello",
                context: context,
                history: [],
                enableWebSearch: true
            )
            
            var fullResponse = ""
            for await result in stream {
                if case .success(let chunk) = result {
                    fullResponse += chunk
                }
            }
            
            XCTAssertFalse(fullResponse.isEmpty, "Should still respond even without Tavily key")
            print("✅ Graceful degradation: \(fullResponse)")
        } else {
            print("⚠️ Tavily key is configured - skipping graceful degradation test")
        }
    }
}
