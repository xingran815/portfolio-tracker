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
    let dataProvider: String?
    
    init(
        symbol: String,
        price: Double,
        change: Double,
        changePercent: Double,
        volume: Int64,
        lastUpdated: Date,
        currency: String,
        dataProvider: String? = nil
    ) {
        self.symbol = symbol
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.volume = volume
        self.lastUpdated = lastUpdated
        self.currency = currency
        self.dataProvider = dataProvider
    }
    
    var formattedPrice: String {
        String(format: "%.2f", price)
    }
    
    var formattedChange: String {
        let sign = change >= 0 ? "+" : ""
        return String(format: "%@%.2f (%@%.2f%%)", sign, change, sign, changePercent)
    }
}

/// Errors that can occur during data fetching
enum DataProviderError: LocalizedError, Sendable {
    case invalidSymbol(String)
    case networkError(underlying: Error)
    case rateLimited
    case invalidResponse
    case decodingError(underlying: Error)
    case apiKeyMissing
    case invalidAPIKey
    case serviceUnavailable
    case noData
    
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
        case .noData:
            return "No data available for this symbol"
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

// MARK: - Mock Implementation

/// Mock data provider for testing and UI development
struct MockDataProvider: DataProviderProtocol {
    
    private let shouldFail: Bool
    private let delay: Duration
    
    init(shouldFail: Bool = false, delay: Duration = .milliseconds(500)) {
        self.shouldFail = shouldFail
        self.delay = delay
    }
    
    func fetchQuote(symbol: String, market: Market) async throws -> Quote {
        try await Task.sleep(for: delay)
        
        if shouldFail {
            throw DataProviderError.networkError(underlying: NSError(domain: "Mock", code: -1))
        }
        
        // Generate deterministic mock price based on symbol
        let hash = abs(symbol.hashValue)
        let basePrice = Double(hash % 1000) + 10.0
        let change = Double(hash % 100) / 10.0 - 5.0
        let changePercent = (change / basePrice) * 100
        
        return Quote(
            symbol: symbol,
            price: basePrice,
            change: change,
            changePercent: changePercent,
            volume: Int64(hash % 1000000),
            lastUpdated: Date(),
            currency: market.currency
        )
    }
    
    func fetchQuotes(symbols: [String], market: Market) async throws -> [String: Quote] {
        var quotes: [String: Quote] = [:]
        for symbol in symbols {
            quotes[symbol] = try await fetchQuote(symbol: symbol, market: market)
        }
        return quotes
    }
}

/// Cache entry for quotes
private struct QuoteCacheEntry: Sendable {
    let quote: Quote
    let timestamp: Date
    
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 86400 // 1 day
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
            now.timeIntervalSince(entry.timestamp) < 86400
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
        cleanOldRequests()
        
        // If at limit, wait until oldest request expires
        if requests.count >= maxRequests, let oldest = requests.first {
            let waitTime = timeWindow - Date().timeIntervalSince(oldest)
            if waitTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
    }
    
    func recordRequest() {
        cleanOldRequests()
        requests.append(Date())
    }
    
    var remainingRequests: Int {
        cleanOldRequests()
        return maxRequests - requests.count
    }
    
    private func cleanOldRequests() {
        let now = Date()
        requests.removeAll { now.timeIntervalSince($0) > timeWindow }
    }
}
