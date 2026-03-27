//
//  ExchangeRateProvider.swift
//  portfolio_tracker
//
//  Service for fetching and caching currency exchange rates
//

import Foundation
import os.log

struct ExchangeRateResponse: Codable {
    let result: String
    let baseCode: String
    let rates: [String: Double]
    
    enum CodingKeys: String, CodingKey {
        case result
        case baseCode = "base_code"
        case rates
    }
}

enum ExchangeRateError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case rateNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的汇率 API URL"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "汇率 API 返回无效数据"
        case .rateNotFound(let currency):
            return "未找到货币 \(currency) 的汇率"
        }
    }
}

actor ExchangeRateProvider {
    
    static let shared = ExchangeRateProvider()
    
    private var cachedRates: [String: [String: Double]] = [:]
    private var cacheTime: [String: Date] = [:]
    private let cacheDuration: TimeInterval = 86400
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "ExchangeRateProvider")
    
    private init() {}
    
    func getRate(from: Currency, to: Currency) async throws -> Double {
        if from == to { return 1.0 }
        
        let baseCode = from.code
        
        if let rates = cachedRates[baseCode],
           let cacheDate = cacheTime[baseCode],
           Date().timeIntervalSince(cacheDate) < cacheDuration,
           let rate = rates[to.code] {
            logger.debug("Using cached rate: \(from.code) -> \(to.code) = \(rate)")
            return rate
        }
        
        let rates = try await fetchRates(base: baseCode)
        
        guard let rate = rates[to.code] else {
            throw ExchangeRateError.rateNotFound(to.code)
        }
        
        return rate
    }
    
    func convert(amount: Double, from: Currency, to: Currency) async throws -> Double {
        let rate = try await getRate(from: from, to: to)
        return amount * rate
    }
    
    func fetchRates(base: String) async throws -> [String: Double] {
        if let rates = cachedRates[base],
           let cacheDate = cacheTime[base],
           Date().timeIntervalSince(cacheDate) < cacheDuration {
            return rates
        }
        
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(base)") else {
            throw ExchangeRateError.invalidURL
        }
        
        logger.info("Fetching exchange rates for base: \(base)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ExchangeRateError.invalidResponse
            }
            
            let exchangeRateResponse = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            
            guard exchangeRateResponse.result == "success" else {
                throw ExchangeRateError.invalidResponse
            }
            
            cachedRates[base] = exchangeRateResponse.rates
            cacheTime[base] = Date()
            
            logger.info("Cached \(exchangeRateResponse.rates.count) exchange rates for \(base)")
            
            return exchangeRateResponse.rates
        } catch let error as ExchangeRateError {
            throw error
        } catch {
            throw ExchangeRateError.networkError(error)
        }
    }
    
    func getCachedRates(base: String) -> [String: Double]? {
        guard let rates = cachedRates[base],
              let cacheDate = cacheTime[base],
              Date().timeIntervalSince(cacheDate) < cacheDuration else {
            return nil
        }
        return rates
    }
    
    func clearCache() {
        cachedRates.removeAll()
        cacheTime.removeAll()
        logger.info("Exchange rate cache cleared")
    }
}
