//
//  DataProviderProtocol.swift
//  portfolio_tracker
//
//  Protocol for price data fetching
//

import Foundation

/// Quote data for a symbol
struct Quote: Sendable {
    let symbol: String
    let price: Double
    let change: Double?
    let changePercent: Double?
    let timestamp: Date
    let currency: String
}

/// Errors from data provider
enum DataProviderError: LocalizedError, Sendable {
    case invalidSymbol(String)
    case networkError(underlying: Error)
    case rateLimited
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidSymbol(let symbol):
            return "Invalid symbol: \(symbol)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .noData:
            return "No data available for this symbol"
        }
    }
}

/// Protocol for price data providers
protocol DataProviderProtocol: Sendable {
    /// Fetches current quote for a symbol
    /// - Parameters:
    ///   - symbol: Stock/fund symbol (e.g., "AAPL")
    ///   - market: Market identifier
    /// - Returns: Quote with current price
    /// - Throws: DataProviderError if fetch fails
    func fetchQuote(symbol: String, market: Market) async throws -> Quote
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
            timestamp: Date(),
            currency: market.currency
        )
    }
}
