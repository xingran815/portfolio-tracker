//
//  AlphaVantageProvider.swift
//  portfolio_tracker
//
//  Alpha Vantage API implementation for price fetching
//

import Foundation
import os.log

/// Alpha Vantage API provider for fetching stock quotes
///
/// Supports US stocks (e.g., "AAPL") and Hong Kong stocks (e.g., "0700.HK")
///
/// Free tier limitations:
/// - 25 API requests per day
/// - 5 requests per minute
///
/// Usage:
/// ```swift
/// let provider = AlphaVantageProvider(apiKeyManager: APIKeyManager.shared)
/// let quote = try await provider.fetchQuote(symbol: "AAPL", market: .us)
/// print("Price: \(quote.price)")
/// ```
actor AlphaVantageProvider: DataProviderProtocol {
    
    // MARK: - Properties
    
    private let apiKeyManager: APIKeyManager
    private let cache = QuoteCache()
    private let rateLimiter: RateLimiter
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "AlphaVantageProvider")
    
    private let baseURL = "https://www.alphavantage.co/query"
    private let urlSession: URLSession
    
    // MARK: - Initialization
    
    /// Creates a new Alpha Vantage provider
    /// - Parameters:
    ///   - apiKeyManager: Keychain manager for API key storage
    ///   - urlSession: URLSession for network requests (default: shared)
    init(
        apiKeyManager: APIKeyManager = .shared,
        urlSession: URLSession = .shared
    ) {
        self.apiKeyManager = apiKeyManager
        self.urlSession = urlSession
        // Free tier: 5 requests per minute
        self.rateLimiter = RateLimiter(maxRequests: 5, perSeconds: 60)
    }
    
    // MARK: - DataProviderProtocol
    
    /// Fetches a quote for the given symbol
    /// - Parameters:
    ///   - symbol: Stock symbol (e.g., "AAPL" for US, "0700.HK" for HK)
    ///   - market: Market identifier (.us, .hk, or .cn)
    /// - Returns: Quote with current price information
    /// - Throws: DataProviderError if request fails
    func fetchQuote(symbol: String, market: Market) async throws -> Quote {
        // Check cache first
        if let cached = await cache.get(symbol: symbol) {
            logger.debug("Using cached quote for \(symbol)")
            return cached
        }
        
        // Get API key
        guard let apiKey = try? await apiKeyManager.getKey(for: .alphaVantage) else {
            logger.error("Alpha Vantage API key not configured")
            throw DataProviderError.apiKeyMissing
        }
        
        // Apply rate limiting
        await rateLimiter.waitIfNeeded()
        
        // Build request
        let url = try buildURL(symbol: symbol, apiKey: apiKey)
        
        logger.info("Fetching quote for \(symbol) from Alpha Vantage")
        
        // Perform request
        let (data, response) = try await performRequest(url: url)
        
        // Record request for rate limiting
        await rateLimiter.recordRequest()
        
        // Parse response
        let quote = try parseResponse(data: data, symbol: symbol, market: market)
        
        // Cache the result
        await cache.set(symbol: symbol, quote: quote)
        
        logger.info("Successfully fetched quote for \(symbol): \(quote.price)")
        
        return quote
    }
    
    /// Fetches multiple quotes with rate limiting between requests
    /// - Parameters:
    ///   - symbols: Array of stock symbols
    ///   - market: Market identifier
    /// - Returns: Dictionary mapping symbols to quotes (failed symbols omitted)
    func fetchQuotes(symbols: [String], market: Market) async throws -> [String: Quote] {
        var results: [String: Quote] = [:]
        
        for symbol in symbols {
            do {
                let quote = try await fetchQuote(symbol: symbol, market: market)
                results[symbol] = quote
            } catch {
                logger.warning("Failed to fetch quote for \(symbol): \(error.localizedDescription)")
                // Continue with other symbols, don't fail entire batch
            }
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    /// Builds the API request URL
    private func buildURL(symbol: String, apiKey: String) throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw DataProviderError.invalidSymbol(symbol)
        }
        
        // Format symbol for Alpha Vantage
        let formattedSymbol = formatSymbol(symbol)
        
        components.queryItems = [
            URLQueryItem(name: "function", value: "GLOBAL_QUOTE"),
            URLQueryItem(name: "symbol", value: formattedSymbol),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        
        guard let url = components.url else {
            throw DataProviderError.invalidSymbol(symbol)
        }
        
        return url
    }
    
    /// Formats symbol for Alpha Vantage API
    /// - HK stocks: 0700.HK (already correct)
    /// - US stocks: AAPL (no change needed)
    private func formatSymbol(_ symbol: String) -> String {
        // Alpha Vantage accepts standard formats
        // HK stocks should be in format: XXXX.HK
        return symbol.uppercased()
    }
    
    /// Performs the network request
    private func performRequest(url: URL) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DataProviderError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                return (data, response)
            case 401:
                throw DataProviderError.invalidAPIKey
            case 429:
                throw DataProviderError.rateLimited
            case 500...599:
                throw DataProviderError.serviceUnavailable
            default:
                throw DataProviderError.invalidResponse
            }
        } catch let error as DataProviderError {
            throw error
        } catch {
            throw DataProviderError.networkError(underlying: error)
        }
    }
    
    /// Parses Alpha Vantage API response
    private func parseResponse(data: Data, symbol: String, market: Market) throws -> Quote {
        struct AlphaVantageResponse: Codable {
            let globalQuote: GlobalQuote?
            
            enum CodingKeys: String, CodingKey {
                case globalQuote = "Global Quote"
            }
            
            struct GlobalQuote: Codable {
                let symbol: String
                let open: String
                let high: String
                let low: String
                let price: String
                let volume: String
                let latestTradingDay: String
                let previousClose: String
                let change: String
                let changePercent: String
                
                enum CodingKeys: String, CodingKey {
                    case symbol = "01. symbol"
                    case open = "02. open"
                    case high = "03. high"
                    case low = "04. low"
                    case price = "05. price"
                    case volume = "06. volume"
                    case latestTradingDay = "07. latest trading day"
                    case previousClose = "08. previous close"
                    case change = "09. change"
                    case changePercent = "10. change percent"
                }
            }
        }
        
        do {
            let response = try JSONDecoder().decode(AlphaVantageResponse.self, from: data)
            
            guard let quote = response.globalQuote else {
                // Check if it's a rate limit message
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let note = json["Note"] as? String,
                   note.contains("API call frequency") {
                    throw DataProviderError.rateLimited
                }
                
                // Check if it's an error message
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = json["Error Message"] as? String {
                    logger.error("Alpha Vantage error: \(errorMessage)")
                    throw DataProviderError.invalidSymbol(symbol)
                }
                
                throw DataProviderError.invalidResponse
            }
            
            // Parse price
            guard let price = Double(quote.price) else {
                throw DataProviderError.invalidResponse
            }
            
            // Parse change
            let change = Double(quote.change) ?? 0.0
            
            // Parse change percent (remove % sign)
            let changePercentString = quote.changePercent.replacingOccurrences(of: "%", with: "")
            let changePercent = Double(changePercentString) ?? 0.0
            
            // Parse volume
            let volume = Int64(quote.volume) ?? 0
            
            // Determine currency based on market
            let currency: String
            switch market {
            case .us:
                currency = "USD"
            case .hk:
                currency = "HKD"
            case .cn:
                currency = "CNY"
            }
            
            return Quote(
                symbol: symbol,
                price: price,
                change: change,
                changePercent: changePercent,
                volume: volume,
                lastUpdated: Date(),
                currency: currency
            )
            
        } catch let error as DataProviderError {
            throw error
        } catch {
            throw DataProviderError.decodingError(underlying: error)
        }
    }
    
    // MARK: - Cache Management
    
    /// Clears the quote cache
    func clearCache() async {
        await cache.clear()
        logger.info("Quote cache cleared")
    }
    
    /// Gets the number of remaining API requests in current window
    var remainingRequests: Int {
        get async {
            await rateLimiter.remainingRequests
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension AlphaVantageProvider {
    /// Mock provider for previews with sample data
    static var preview: AlphaVantageProvider {
        get async {
            // Create a mock provider with a mock URLSession
            let provider = AlphaVantageProvider()
            return provider
        }
    }
}
#endif
