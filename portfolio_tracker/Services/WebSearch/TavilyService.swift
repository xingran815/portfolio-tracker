//
//  TavilyService.swift
//  portfolio_tracker
//
//  Tavily API service for web search functionality
//

import Foundation
import os.log

actor TavilyService {
    
    static let shared = TavilyService()
    
    private let apiKeyManager: APIKeyManager
    private let baseURL = "https://api.tavily.com"
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "TavilyService")
    
    private let urlSession: URLSession
    private let maxRetries = 2
    
    init(apiKeyManager: APIKeyManager = .shared) {
        self.apiKeyManager = apiKeyManager
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.urlSession = URLSession(configuration: config)
    }
    
    /// Search with auto-detected topic
    func search(query: String) async throws -> TavilySearchResult {
        guard let apiKey = try? await apiKeyManager.getKey(for: .tavily) else {
            throw TavilyError.apiKeyNotConfigured
        }
        
        let topic = detectTopic(for: query)
        let timeRange = topic == "news" ? "week" : nil
        
        let options = TavilySearchOptions(
            maxResults: 5,
            searchDepth: "basic",
            includeAnswer: true,
            topic: topic,
            timeRange: timeRange
        )
        
        return try await search(query: query, options: options, apiKey: apiKey)
    }
    
    /// Search with explicit options
    func search(query: String, options: TavilySearchOptions = .default) async throws -> TavilySearchResult {
        guard let apiKey = try? await apiKeyManager.getKey(for: .tavily) else {
            throw TavilyError.apiKeyNotConfigured
        }
        
        return try await search(query: query, options: options, apiKey: apiKey)
    }
    
    /// Search with retry logic
    func search(query: String, options: TavilySearchOptions, apiKey: String) async throws -> TavilySearchResult {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await performSearch(query: query, options: options, apiKey: apiKey)
            } catch let error as TavilyError {
                lastError = error
                
                // Only retry on transient errors
                switch error {
                case .networkError, .rateLimited, .timeout:
                    if attempt < maxRetries - 1 {
                        let delay = UInt64(1_000_000_000 * (attempt + 1))
                        logger.warning("Tavily search failed (attempt \(attempt + 1)), retrying in \(delay/1_000_000_000)s...")
                        try await Task.sleep(nanoseconds: delay)
                    }
                case .invalidAPIKey, .apiKeyNotConfigured, .quotaExceeded:
                    // Don't retry these - they won't succeed
                    throw error
                case .invalidResponse, .noResults:
                    if attempt < maxRetries - 1 {
                        let delay = UInt64(500_000_000 * (attempt + 1))
                        logger.warning("Tavily search failed (attempt \(attempt + 1)), retrying...")
                        try await Task.sleep(nanoseconds: delay)
                    }
                }
            } catch {
                lastError = error
            }
        }
        
        throw lastError ?? TavilyError.networkError("Unknown error after retries")
    }
    
    /// Performs the actual search API call
    private func performSearch(query: String, options: TavilySearchOptions, apiKey: String) async throws -> TavilySearchResult {
        guard let url = URL(string: "\(baseURL)/search") else {
            throw TavilyError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var body: [String: Any] = [
            "query": query,
            "max_results": options.maxResults,
            "search_depth": options.searchDepth,
            "include_answer": options.includeAnswer,
            "topic": options.topic
        ]
        
        if let timeRange = options.timeRange {
            body["time_range"] = timeRange
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        logger.info("Searching Tavily for: \(query) (topic: \(options.topic))")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TavilyError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw TavilyError.invalidAPIKey
        case 429:
            throw TavilyError.rateLimited
        case 432, 433:
            throw TavilyError.quotaExceeded
        case 408, 504:
            throw TavilyError.timeout
        default:
            if let errorResponse = try? JSONDecoder().decode(TavilyAPIError.self, from: data),
               let errorMessage = errorResponse.detail?.error {
                throw TavilyError.networkError(errorMessage)
            }
            throw TavilyError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(TavilyAPIResponse.self, from: data)
        
        let result = TavilySearchResult(
            query: apiResponse.query,
            answer: apiResponse.answer,
            results: apiResponse.results,
            responseTime: apiResponse.responseTime
        )
        
        logger.info("Tavily search completed in \(apiResponse.responseTime)s with \(apiResponse.results.count) results")
        
        return result
    }
    
    /// Auto-detects appropriate search topic based on query content
    private func detectTopic(for query: String) -> String {
        let queryLower = query.lowercased()
        
        // News indicators
        let newsIndicators = [
            "最新", "新闻", "今天", "昨天", "本周", "近期", "突发", "刚刚",
            "latest", "news", "today", "yesterday", "this week", "breaking", "just in",
            "宣布", "发布", "声明", "announced", "released", "statement"
        ]
        
        // General/educational indicators
        let generalIndicators = [
            "如何", "什么是", "为什么", "怎么", "介绍", "解释", "说明",
            "how to", "what is", "why", "explain", "guide", "tutorial",
            "定义", "概念", "原理", "definition", "concept"
        ]
        
        // Check news first
        if newsIndicators.contains(where: { queryLower.contains($0.lowercased()) }) {
            return "news"
        }
        
        // Check general
        if generalIndicators.contains(where: { queryLower.contains($0.lowercased()) }) {
            return "general"
        }
        
        // Default to finance (this is a portfolio app after all)
        return "finance"
    }
    
    func validateAPIKey() async -> APIKeyValidationResult {
        guard let apiKey = try? await apiKeyManager.getKey(for: .tavily) else {
            return .notConfigured
        }
        
        // Quick format validation (no API call, no credits used)
        guard apiKey.hasPrefix("tvly-") && apiKey.count > 10 else {
            return .invalid
        }
        
        return .valid
    }
    
    /// Full validation with test search (uses 1 credit)
    /// Only call when user explicitly clicks "Validate" button
    func validateAPIKeyWithSearch() async -> APIKeyValidationResult {
        guard let apiKey = try? await apiKeyManager.getKey(for: .tavily) else {
            return .notConfigured
        }
        
        // Format check first
        guard apiKey.hasPrefix("tvly-") && apiKey.count > 10 else {
            return .invalid
        }
        
        // Make minimal test search (1 credit)
        do {
            _ = try await search(
                query: "test",
                options: TavilySearchOptions(
                    maxResults: 1,
                    searchDepth: "basic",
                    includeAnswer: false,
                    topic: "general",
                    timeRange: nil
                ),
                apiKey: apiKey
            )
            return .valid
        } catch TavilyError.invalidAPIKey {
            return .invalid
        } catch TavilyError.rateLimited {
            return .rateLimited
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
    
    func isConfigured() async -> Bool {
        await apiKeyManager.hasKey(for: .tavily)
    }
}
