//
//  DataProviderProtocol.swift
//  portfolio_tracker
//
//  Protocol for fetching stock quotes
//

import Foundation

/// Quote data structure
struct Quote: Sendable, Codable {
    let symbol: String
    let price: Double
    let change: Double
    let changePercent: Double
    let volume: Int64
    let lastUpdated: Date
    let currency: String
    
    /// Convenience computed property for formatted price
    var formattedPrice: String {
        String(format: "%.2f", price)
    }
    
    /// Convenience computed property for formatted change
    var formattedChange: String {
        let sign = change >= 0 ? "+" : ""
        return String(format: "%@%.2f (%@%.2f%%)", sign, change, sign, changePercent)
    }
}

/// Errors that can occur during data fetching
enum DataProviderError: LocalizedError {
    case invalidSymbol(String)
    case networkError(underlying: Error)
    case rateLimited
    case invalidResponse
    case decodingError(underlying: Error)
    case apiKeyMissing
    case invalidAPIKey
    case serviceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidSymbol(let symbol):
            return "Invalid symbol: \(symbol)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limit exceeded. Please wait before making more requests."
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .apiKeyMissing:
            return "API key not configured. Please add your Alpha Vantage API key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your Alpha Vantage API key in Settings."
        case .serviceUnavailable:
            return "Alpha Vantage service is temporarily unavailable"
        }
    }
}

/// Protocol for price fetching providers
protocol DataProviderProtocol: Sendable {
    /// Fetches a quote for the given symbol
    /// - Parameters:
    ///   - symbol: Stock symbol (e.g., "AAPL", "0700.HK")
    ///   - market: Market identifier
    /// - Returns: Quote with current price information
    /// - Throws: DataProviderError if request fails
    func fetchQuote(symbol: String, market: Market) async throws -> Quote
    
    /// Fetches multiple quotes in a batch
    /// - Parameters:
    ///   - symbols: Array of stock symbols
    ///   - market: Market identifier
    /// - Returns: Dictionary mapping symbols to quotes
    /// - Throws: DataProviderError if request fails
    func fetchQuotes(symbols: [String], market: Market) async throws -> [String: Quote]
}

/// Cache entry for quotes
private struct QuoteCacheEntry: Sendable {
    let quote: Quote
    let timestamp: Date
    
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 300 // 5 minutes
    }
}

/// Actor-based cache for thread-safe quote caching
actor QuoteCache {
    private var cache: [String: QuoteCacheEntry] = [:]
    
    func get(symbol: String) -> Quote? {
        guard let entry = cache[symbol], entry.isValid else {
            cache.removeValue(forKey: symbol)
            return nil
        }
        return entry.quote
    }
    
    func set(symbol: String, quote: Quote) {
        cache[symbol] = QuoteCacheEntry(quote: quote, timestamp: Date())
    }
    
    func clear() {
        cache.removeAll()
    }
    
    func clearExpired() {
        let now = Date()
        cache = cache.filter { _, entry in
            now.timeIntervalSince(entry.timestamp) < 300
        }
    }
}

/// Rate limiter for API requests
actor RateLimiter {
    private var requests: [Date] = []
    private let maxRequests: Int
    private let timeWindow: TimeInterval
    
    init(maxRequests: Int, perSeconds: TimeInterval) {
        self.maxRequests = maxRequests
        self.timeWindow = perSeconds
    }
    
    func waitIfNeeded() async {
        let now = Date()
        // Remove old requests outside the time window
        requests.removeAll { now.timeIntervalSince($0) > timeWindow }
        
        // If at limit, wait until oldest request expires
        if requests.count >= maxRequests, let oldest = requests.first {
            let waitTime = timeWindow - now.timeIntervalSince(oldest)
            if waitTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
    }
    
    func recordRequest() {
        requests.append(Date())
    }
    
    var remainingRequests: Int {
        maxRequests - requests.count
    }
}
