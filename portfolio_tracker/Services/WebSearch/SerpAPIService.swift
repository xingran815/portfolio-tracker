//
//  SerpAPIService.swift
//  portfolio_tracker
//
//  SerpAPI service for web search functionality
//

import Foundation
import os.log

actor SerpAPIService {
    
    static let shared = SerpAPIService()
    
    private let apiKeyManager: APIKeyManager
    private let baseURL = "https://serpapi.com/search"
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "SerpAPIService")
    
    private let urlSession: URLSession
    private let maxRetries = 2
    
    init(apiKeyManager: APIKeyManager = .shared) {
        self.apiKeyManager = apiKeyManager
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.urlSession = URLSession(configuration: config)
    }
    
    func search(query: String) async throws -> SerpSearchResult {
        guard let apiKey = try? await apiKeyManager.getKey(for: .serpAPI) else {
            throw SerpAPIError.apiKeyNotConfigured
        }
        
        let options = SerpSearchOptions.default
        return try await search(query: query, options: options, apiKey: apiKey)
    }
    
    func search(query: String, options: SerpSearchOptions) async throws -> SerpSearchResult {
        guard let apiKey = try? await apiKeyManager.getKey(for: .serpAPI) else {
            throw SerpAPIError.apiKeyNotConfigured
        }
        
        return try await search(query: query, options: options, apiKey: apiKey)
    }
    
    func search(query: String, options: SerpSearchOptions, apiKey: String) async throws -> SerpSearchResult {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await performSearch(query: query, options: options, apiKey: apiKey)
            } catch let error as SerpAPIError {
                lastError = error
                
                switch error {
                case .networkError, .rateLimited, .timeout:
                    if attempt < maxRetries - 1 {
                        let delay = UInt64(1_000_000_000 * (attempt + 1))
                        logger.warning("SerpAPI search failed (attempt \(attempt + 1)), retrying in \(delay/1_000_000_000)s...")
                        try await Task.sleep(nanoseconds: delay)
                    }
                case .invalidAPIKey, .apiKeyNotConfigured, .quotaExceeded:
                    throw error
                case .invalidResponse, .noResults:
                    if attempt < maxRetries - 1 {
                        let delay = UInt64(500_000_000 * (attempt + 1))
                        logger.warning("SerpAPI search failed (attempt \(attempt + 1)), retrying...")
                        try await Task.sleep(nanoseconds: delay)
                    }
                }
            } catch {
                lastError = error
            }
        }
        
        throw lastError ?? SerpAPIError.networkError("Unknown error after retries")
    }
    
    private func performSearch(query: String, options: SerpSearchOptions, apiKey: String) async throws -> SerpSearchResult {
        var urlComponents = URLComponents(string: baseURL)!
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "num", value: String(options.numResults)),
            URLQueryItem(name: "hl", value: options.language),
            URLQueryItem(name: "gl", value: options.country)
        ]
        
        if let location = options.location {
            queryItems.append(URLQueryItem(name: "location", value: location))
        }
        
        if let googleDomain = options.googleDomain {
            queryItems.append(URLQueryItem(name: "google_domain", value: googleDomain))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw SerpAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        logger.info("Searching SerpAPI for: \(query) (gl: \(options.country), hl: \(options.language))")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SerpAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw SerpAPIError.invalidAPIKey
        case 429:
            throw SerpAPIError.rateLimited
        case 408, 504:
            throw SerpAPIError.timeout
        default:
            if let errorResponse = try? JSONDecoder().decode(SerpAPIErrorResponse.self, from: data),
               let errorMessage = errorResponse.error {
                throw SerpAPIError.networkError(errorMessage)
            }
            throw SerpAPIError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(SerpAPIResponse.self, from: data)
        
        guard let organicResults = apiResponse.organicResults, !organicResults.isEmpty else {
            throw SerpAPIError.noResults
        }
        
        let resultItems = organicResults.compactMap { result -> SerpSearchResultItem? in
            guard let title = result.title,
                  let link = result.link else {
                return nil
            }
            return SerpSearchResultItem(
                title: title,
                url: link,
                snippet: result.snippet ?? "",
                position: result.position ?? 0
            )
        }
        
        let result = SerpSearchResult(
            query: apiResponse.searchParameters?.q ?? query,
            results: resultItems,
            totalResults: apiResponse.searchInformation?.totalResults,
            searchTime: apiResponse.searchMetadata?.totalTimeTaken
        )
        
        logger.info("SerpAPI search completed with \(resultItems.count) results")
        
        return result
    }
    
    func validateAPIKey() async -> APIKeyValidationResult {
        guard let apiKey = try? await apiKeyManager.getKey(for: .serpAPI) else {
            return .notConfigured
        }
        
        guard apiKey.count >= 30 else {
            return .invalid
        }
        
        return .valid
    }
    
    func validateAPIKeyWithSearch() async -> APIKeyValidationResult {
        guard let apiKey = try? await apiKeyManager.getKey(for: .serpAPI) else {
            return .notConfigured
        }
        
        guard apiKey.count >= 30 else {
            return .invalid
        }
        
        do {
            _ = try await search(
                query: "test",
                options: SerpSearchOptions(numResults: 1, language: "en", country: "us", location: nil, googleDomain: nil),
                apiKey: apiKey
            )
            return .valid
        } catch SerpAPIError.invalidAPIKey {
            return .invalid
        } catch SerpAPIError.rateLimited {
            return .rateLimited
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
    
    func isConfigured() async -> Bool {
        await apiKeyManager.hasKey(for: .serpAPI)
    }
}

struct SerpSearchOptions: Sendable {
    let numResults: Int
    let language: String
    let country: String
    let location: String?
    let googleDomain: String?
    
    static let `default` = SerpSearchOptions(
        numResults: 5,
        language: "zh-CN",
        country: "cn",
        location: nil,
        googleDomain: nil
    )
    
    static let news = SerpSearchOptions(
        numResults: 5,
        language: "zh-CN",
        country: "cn",
        location: nil,
        googleDomain: nil
    )
    
    static let hongKong = SerpSearchOptions(
        numResults: 5,
        language: "zh-TW",
        country: "hk",
        location: nil,
        googleDomain: "google.com.hk"
    )
}
