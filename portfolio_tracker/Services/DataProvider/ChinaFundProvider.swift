//
//  ChinaFundProvider.swift
//  portfolio_tracker
//
//  Data provider for Chinese mutual funds using 天天基金 API
//

import Foundation
import os.log

// MARK: - Response Models

private struct TianTianFundResponse: Codable {
    let fundcode: String
    let name: String
    let jzrq: String
    let dwjz: String
    let gsz: String?
    let gszzl: String?
    let gztime: String?
}

// MARK: - Errors

enum ChinaFundProviderError: LocalizedError, Sendable {
    case invalidFundCode
    case noData
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFundCode:
            return "基金代码格式错误，应为6位数字"
        case .noData:
            return "未找到该基金数据"
        case .networkError(let message):
            return "网络错误: \(message)"
        }
    }
}

// MARK: - Provider

actor ChinaFundProvider: DataProviderProtocol {
    
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "ChinaFundProvider")
    private let cache = QuoteCache()
    
    // MARK: - DataProviderProtocol
    
    func fetchQuote(symbol: String, market: Market) async throws -> Quote {
        try validateFundCode(symbol)
        
        if let cached = await cache.get(symbol: symbol) {
            logger.debug("Using cached quote for \(symbol)")
            return cached
        }
        
        let quote = try await fetchFromTianTian(symbol: symbol)
        await cache.set(symbol: symbol, quote: quote)
        logger.info("Fetched fund price from 天天基金 for \(symbol): NAV \(quote.price)")
        return quote
    }
    
    func fetchQuotes(symbols: [String], market: Market) async throws -> [String: Quote] {
        var results: [String: Quote] = [:]
        for symbol in symbols {
            do {
                results[symbol] = try await fetchQuote(symbol: symbol, market: market)
            } catch {
                logger.warning("Failed to fetch fund price for \(symbol): \(error.localizedDescription)")
            }
        }
        return results
    }
    
    // MARK: - 天天基金 API
    
    private func fetchFromTianTian(symbol: String) async throws -> Quote {
        let url = URL(string: "https://fundgz.1234567.com.cn/js/\(symbol).js")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ChinaFundProviderError.noData
        }
        
        guard jsonString.contains("jsonpgz(") else {
            throw ChinaFundProviderError.noData
        }
        
        let jsonData = try parseJSONP(jsonString)
        let response = try JSONDecoder().decode(TianTianFundResponse.self, from: jsonData)
        
        guard let nav = Double(response.dwjz) else {
            throw ChinaFundProviderError.noData
        }
        
        let changePercent = Double(response.gszzl ?? "0") ?? 0
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let lastUpdated = dateFormatter.date(from: response.jzrq) ?? Date()
        
        return Quote(
            symbol: symbol,
            price: nav,
            change: 0,
            changePercent: changePercent,
            volume: 0,
            lastUpdated: lastUpdated,
            currency: "CNY",
            dataProvider: "天天基金"
        )
    }
    
    // MARK: - Helpers
    
    private func validateFundCode(_ code: String) throws {
        guard code.count == 6, code.allSatisfy({ $0.isNumber }) else {
            throw ChinaFundProviderError.invalidFundCode
        }
    }
    
    private func parseJSONP(_ jsonp: String) throws -> Data {
        guard jsonp.hasPrefix("jsonpgz(") && jsonp.hasSuffix(");") else {
            throw ChinaFundProviderError.noData
        }
        
        let start = jsonp.index(jsonp.startIndex, offsetBy: 8)
        let end = jsonp.index(jsonp.endIndex, offsetBy: -2)
        let jsonString = String(jsonp[start..<end])
        
        guard let data = jsonString.data(using: .utf8) else {
            throw ChinaFundProviderError.noData
        }
        
        return data
    }
}
