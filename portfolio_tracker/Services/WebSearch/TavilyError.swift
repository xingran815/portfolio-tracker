//
//  TavilyError.swift
//  portfolio_tracker
//
//  Error types for Tavily web search service
//

import Foundation

enum TavilyError: LocalizedError, Sendable {
    case invalidAPIKey
    case rateLimited
    case quotaExceeded
    case networkError(String)
    case invalidResponse
    case noResults
    case apiKeyNotConfigured
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid Tavily API key. Please check your settings."
        case .rateLimited:
            return "Too many search requests. Please wait a moment."
        case .quotaExceeded:
            return "Tavily quota exceeded. Free tier: 1,000 searches/month."
        case .networkError(let message):
            return "Search failed: \(message)"
        case .invalidResponse:
            return "Invalid response from search service."
        case .noResults:
            return "No search results found."
        case .apiKeyNotConfigured:
            return "Tavily API key not configured. Please add it in Settings."
        case .timeout:
            return "Search request timed out."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidAPIKey:
            return "Get a new API key at https://app.tavily.com"
        case .rateLimited:
            return "Wait a few seconds before searching again."
        case .quotaExceeded:
            return "Upgrade your Tavily plan or wait for quota reset."
        case .networkError:
            return "Check your internet connection."
        case .invalidResponse:
            return "Try again or use a different search query."
        case .noResults:
            return "Try different search keywords."
        case .apiKeyNotConfigured:
            return "Add your Tavily API key in Settings to enable web search."
        case .timeout:
            return "Try a simpler search query."
        }
    }
}
