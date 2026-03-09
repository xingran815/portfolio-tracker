//
//  MDParserProtocol.swift
//  portfolio_tracker
//
//  Protocol for Markdown portfolio configuration parser
//

import Foundation

/// Protocol for parsing Markdown portfolio configuration files
protocol MDParserProtocol: Sendable {
    /// Parses markdown content into portfolio configuration
    /// - Parameter content: Markdown text to parse
    /// - Returns: Parsed portfolio configuration
    /// - Throws: MDParserError if parsing fails
    func parse(_ content: String) throws -> PortfolioConfig
}

/// Configuration options for MDParser
struct MDParserConfiguration: Sendable {
    /// Whether to allow partial parsing (skip invalid positions)
    let allowPartialParsing: Bool
    /// Default market for positions without explicit market
    let defaultMarket: Market
    /// Default asset type for positions without explicit type
    let defaultAssetType: AssetType
    
    static let `default` = MDParserConfiguration(
        allowPartialParsing: false,
        defaultMarket: .us,
        defaultAssetType: .stock
    )
}
