//
//  MDParser.swift
//  portfolio_tracker
//
//  Markdown portfolio configuration parser implementation
//

import Foundation

// MARK: - Field Mapping Constants

/// Centralized field name mappings for bilingual support
private enum FieldMapping {
    /// Risk profile field names (English and Chinese)
    static let riskProfile = ["风险偏好", "riskprofile", "risk"]
    
    /// Currency field names
    static let currency = ["货币", "currency", "币种"]
    
    /// Expected return field names
    static let expectedReturn = ["预期收益", "expectedreturn", "return", "目标收益"]
    
    /// Max drawdown field names
    static let maxDrawdown = ["最大回撤", "maxdrawdown", "drawdown"]
    
    /// Rebalancing frequency field names
    static let rebalancingFrequency = ["调仓频率", "rebalancingfrequency", "frequency", "再平衡频率"]
    
    /// Column header keywords for table parsing
    static let symbolColumn = ["代码", "symbol", "股票"]
    static let nameColumn = ["名称", "name", "股票名称"]
    static let typeColumn = ["类型", "type", "assettype"]
    static let marketColumn = ["市场", "market", "交易所"]
    static let sharesColumn = ["数量", "shares", "股数", "持仓"]
    static let costColumn = ["成本", "cost", "costbasis", "买入价"]
    static let ratioColumn = ["比例", "ratio", "percentage", "占比"]
}

// MARK: - Chinese Stock Code Patterns

/// Chinese A-share stock code patterns
/// - 6-digit numeric codes starting with:
///   - 0: Shenzhen small/medium boards (002xxx, 003xxx)
///   - 3: Shenzhen ChiNext/GEM (300xxx, 301xxx)
///   - 6: Shanghai main board (600xxx, 601xxx, 603xxx, 605xxx)
///   - 68: Shanghai STAR market (688xxx)
/// Reference: https://www.szse.cn/English/
///            http://english.sse.com.cn/
private enum ChineseStockPatterns {
    /// Pattern for mainland China A-shares (6 digits)
    static let mainlandCodeLength = 6
    
    /// Valid first digits for mainland exchanges
    static let mainlandFirstDigits: Set<Character> = ["0", "3", "6"]
    
    /// Minimum digits for numeric-only symbols to be considered potential stock codes
    static let minNumericCodeLength = 4
}

// MARK: - Symbol Validation

/// Validates and sanitizes stock symbols
private enum SymbolValidator {
    /// Maximum length for a stock symbol
    static let maxSymbolLength = 20
    
    /// Allowed characters in stock symbols (alphanumeric, dots, hyphens)
    static let allowedCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: ".-"))
    
    /// Validates a symbol and returns sanitized version or nil if invalid
    static func validate(_ symbol: String) -> String? {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces)
        
        // Check length
        guard !trimmed.isEmpty, trimmed.count <= maxSymbolLength else {
            return nil
        }
        
        // Check allowed characters
        let symbolSet = CharacterSet(charactersIn: trimmed)
        guard allowedCharacters.isSuperset(of: symbolSet) else {
            return nil
        }
        
        return trimmed.uppercased()
    }
}

// MARK: - Parser Implementation

/// Parser for Markdown portfolio configuration files
struct MDParser: MDParserProtocol {
    
    // MARK: - Properties
    
    private let configuration: MDParserConfiguration
    
    // MARK: - Initialization
    
    /// Creates a new MDParser with optional configuration
    /// - Parameter configuration: Parser configuration options
    init(configuration: MDParserConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Public Methods
    
    /// Parses markdown content into portfolio configuration
    /// - Parameter content: Markdown text to parse
    /// - Returns: Parsed portfolio configuration
    /// - Throws: MDParserError if parsing fails
    func parse(_ content: String) throws -> PortfolioConfig {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MDParserError.emptyContent
        }
        
        let lines = content.components(separatedBy: .newlines)
        var index = 0
        
        // Parse portfolio name (required)
        let name = try parsePortfolioName(lines: lines, index: &index)
        
        // Parse metadata (optional key-value pairs)
        let metadata = try parseMetadata(lines: lines, index: &index)
        
        // Parse target allocation if present
        let targetAllocation = try parseTargetAllocationSection(lines: lines, index: &index)
        
        // Parse positions
        let positions = try parsePositionsSection(lines: lines, index: &index)
        
        // Build configuration
        return PortfolioConfig(
            name: name,
            riskProfile: metadata.riskProfile,
            currency: metadata.currency,
            expectedReturn: metadata.expectedReturn,
            maxDrawdown: metadata.maxDrawdown,
            rebalancingFrequency: metadata.rebalancingFrequency,
            targetAllocation: targetAllocation,
            positions: positions
        )
    }
}

// MARK: - Private Parsing Methods

private extension MDParser {
    
    /// Metadata structure for intermediate parsing
    struct ParsedMetadata {
        var riskProfile: RiskProfile?
        var currency: Currency?
        var expectedReturn: Double?
        var maxDrawdown: Double?
        var rebalancingFrequency: RebalancingFrequency?
    }
    
    /// Parses the portfolio name from the first h1 header
    func parsePortfolioName(lines: [String], index: inout Int) throws -> String {
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            
            // Look for h1 header
            if line.hasPrefix("# ") {
                let name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else {
                    throw MDParserError.missingPortfolioName
                }
                return name
            }
            
            // Skip empty lines before header
            if !line.isEmpty && !line.hasPrefix("#") {
                throw MDParserError.missingPortfolioName
            }
        }
        
        throw MDParserError.missingPortfolioName
    }
    
    /// Parses metadata key-value pairs
    func parseMetadata(lines: [String], index: inout Int) throws -> ParsedMetadata {
        var metadata = ParsedMetadata()
        
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            
            // Stop at next section header or table
            if line.hasPrefix("##") || line.hasPrefix("|") || line.hasPrefix("- ") {
                break
            }
            
            // Parse key-value pair using safe string splitting
            if line.hasPrefix("- ") {
                let content = String(line.dropFirst(2))
                let parts = content.split(separator: ":", maxSplits: 1)
                
                guard parts.count == 2 else {
                    index += 1
                    continue
                }
                
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                
                try parseMetadataKey(key: key, value: value, metadata: &metadata)
            }
            
            index += 1
        }
        
        return metadata
    }
    
    /// Parses a single metadata key-value pair
    func parseMetadataKey(key: String, value: String, metadata: inout ParsedMetadata) throws {
        let normalizedKey = key.lowercased().replacingOccurrences(of: " ", with: "")
        
        switch normalizedKey {
        case let key where FieldMapping.riskProfile.contains(key):
            guard let profile = RiskProfile(rawValue: value.lowercased()) else {
                throw MDParserError.invalidRiskProfile(value)
            }
            metadata.riskProfile = profile
            
        case let key where FieldMapping.currency.contains(key):
            let upperValue = value.uppercased()
            if let curr = Currency(rawValue: upperValue) {
                metadata.currency = curr
            } else {
                // Try common currency name mappings
                switch upperValue {
                case "USD", "美元", "$":
                    metadata.currency = .usd
                case "CNY", "RMB", "人民币", "¥":
                    metadata.currency = .cny
                case "EUR", "欧元", "€":
                    metadata.currency = .eur
                case "HKD", "港币", "HK$":
                    metadata.currency = .hkd
                case "GBP", "英镑", "£":
                    metadata.currency = .gbp
                case "JPY", "日元":
                    metadata.currency = .jpy
                default:
                    break
                }
            }
            
        case let key where FieldMapping.expectedReturn.contains(key):
            metadata.expectedReturn = try parsePercentageOrDecimal(value, field: "expectedReturn")
            
        case let key where FieldMapping.maxDrawdown.contains(key):
            metadata.maxDrawdown = try parsePercentageOrDecimal(value, field: "maxDrawdown")
            
        case let key where FieldMapping.rebalancingFrequency.contains(key):
            let normalizedValue = value.lowercased()
            if normalizedValue == "monthly" || normalizedValue == "每月" {
                metadata.rebalancingFrequency = .monthly
            } else if normalizedValue == "quarterly" || normalizedValue == "每季度" {
                metadata.rebalancingFrequency = .quarterly
            } else {
                throw MDParserError.invalidRebalancingFrequency(value)
            }
            
        default:
            // Unknown key, ignore
            break
        }
    }
    
    /// Parses target allocation section if present
    func parseTargetAllocationSection(lines: [String], index: inout Int) throws -> [String: Double]? {
        var allocation: [String: Double] = [:]
        
        // Look for target allocation section header
        guard index < lines.count else { return nil }
        
        let headerLine = lines[index].trimmingCharacters(in: .whitespaces)
        let isTargetSection = headerLine.contains("目标配置") || 
                              headerLine.lowercased().contains("target") ||
                              headerLine.lowercased().contains("allocation")
        
        guard isTargetSection && headerLine.hasPrefix("##") else {
            return nil
        }
        
        index += 1
        
        // Skip to table
        while index < lines.count && !lines[index].hasPrefix("|") {
            index += 1
        }
        
        // Parse table
        guard index < lines.count else { return allocation }
        
        let (headers, headerIndex) = try parseTableHeaders(lines: lines, index: &index)
        
        guard let symbolCol = findColumnIndex(headers: headers, keywords: FieldMapping.symbolColumn),
              let ratioCol = findColumnIndex(headers: headers, keywords: FieldMapping.ratioColumn) else {
            // Not a target allocation table, skip
            index = headerIndex
            return nil
        }
        
        // Parse data rows
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { break }
            
            let cells = parseTableRow(line)
            guard cells.count > max(symbolCol, ratioCol) else {
                index += 1
                continue
            }
            
            let symbol = cells[symbolCol].trimmingCharacters(in: .whitespaces)
            let ratioString = cells[ratioCol].trimmingCharacters(in: .whitespaces)
            
            guard !symbol.isEmpty else {
                index += 1
                continue
            }
            
            // Validate symbol before processing
            guard let validatedSymbol = SymbolValidator.validate(symbol) else {
                if !configuration.allowPartialParsing {
                    throw MDParserError.invalidPositionFormat(line: "Invalid symbol: \(symbol)")
                }
                index += 1
                continue
            }
            
            do {
                let ratio = try parsePercentageOrDecimal(ratioString, field: "targetAllocation")
                allocation[validatedSymbol] = ratio
            } catch {
                if !configuration.allowPartialParsing {
                    throw error
                }
            }
            
            index += 1
        }
        
        return allocation.isEmpty ? nil : allocation
    }
    
    /// Parses the positions section
    func parsePositionsSection(lines: [String], index: inout Int) throws -> [PositionConfig] {
        var positions: [PositionConfig] = []
        
        // Skip to positions section or table
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            
            // Check for positions section header
            if line.hasPrefix("##") {
                let headerContent = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if headerContent.contains("持仓") || 
                   headerContent.lowercased().contains("position") ||
                   headerContent.lowercased().contains("holding") {
                    index += 1
                    break
                }
            }
            
            // Direct table (no header)
            if line.hasPrefix("|") {
                break
            }
            
            index += 1
        }
        
        // Skip empty lines
        while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }
        
        guard index < lines.count else { return positions }
        
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        
        if line.hasPrefix("|") {
            // Table format
            positions = try parsePositionsTable(lines: lines, index: &index)
        } else if line.hasPrefix("- ") {
            // List format
            positions = try parsePositionsList(lines: lines, index: &index)
        }
        
        return positions
    }
}

// MARK: - Table Parsing

private extension MDParser {
    
    /// Parses table headers and returns column names
    func parseTableHeaders(lines: [String], index: inout Int) throws -> ([String], Int) {
        guard index < lines.count else {
            throw MDParserError.invalidTableFormat
        }
        
        let headerLine = lines[index].trimmingCharacters(in: .whitespaces)
        guard headerLine.hasPrefix("|") else {
            throw MDParserError.invalidTableFormat
        }
        
        let headers = parseTableRow(headerLine)
        index += 1
        
        // Skip separator line (|---|---|)
        if index < lines.count {
            let separatorLine = lines[index].trimmingCharacters(in: .whitespaces)
            if separatorLine.hasPrefix("|") && separatorLine.contains("-") {
                index += 1
            }
        }
        
        return (headers, index)
    }
    
    /// Parses a table row into cells
    func parseTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        var currentCell = ""
        var insideCell = false
        
        for char in line {
            if char == "|" {
                if insideCell {
                    cells.append(currentCell.trimmingCharacters(in: .whitespaces))
                    currentCell = ""
                }
                insideCell = true
            } else {
                currentCell.append(char)
            }
        }
        
        // Handle last cell if line doesn't end with |
        if !currentCell.isEmpty {
            cells.append(currentCell.trimmingCharacters(in: .whitespaces))
        }
        
        // Remove first empty cell if line starts with |
        if cells.first?.isEmpty == true {
            cells.removeFirst()
        }
        
        return cells
    }
    
    /// Parses positions from table format
    func parsePositionsTable(lines: [String], index: inout Int) throws -> [PositionConfig] {
        var positions: [PositionConfig] = []
        var seenSymbols: Set<String> = []
        
        let (headers, _) = try parseTableHeaders(lines: lines, index: &index)
        
        // Map column indices using centralized mappings
        let symbolCol = findColumnIndex(headers: headers, keywords: FieldMapping.symbolColumn)
        let nameCol = findColumnIndex(headers: headers, keywords: FieldMapping.nameColumn)
        let typeCol = findColumnIndex(headers: headers, keywords: FieldMapping.typeColumn)
        let marketCol = findColumnIndex(headers: headers, keywords: FieldMapping.marketColumn)
        let sharesCol = findColumnIndex(headers: headers, keywords: FieldMapping.sharesColumn)
        let costCol = findColumnIndex(headers: headers, keywords: FieldMapping.costColumn)
        
        guard let symbolCol = symbolCol, let sharesCol = sharesCol else {
            throw MDParserError.invalidTableFormat
        }
        
        // Parse data rows
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { break }
            
            let cells = parseTableRow(line)
            guard cells.count > max(symbolCol, sharesCol) else {
                index += 1
                continue
            }
            
            let symbol = cells[symbolCol].trimmingCharacters(in: .whitespaces)
            let sharesString = cells[sharesCol].trimmingCharacters(in: .whitespaces)
            
            // Validate symbol
            guard let validatedSymbol = SymbolValidator.validate(symbol) else {
                if !configuration.allowPartialParsing {
                    throw MDParserError.invalidPositionFormat(line: "Invalid symbol: \(symbol)")
                }
                index += 1
                continue
            }
            
            // Check for duplicates
            if seenSymbols.contains(validatedSymbol) {
                if !configuration.allowPartialParsing {
                    throw MDParserError.duplicateSymbol(validatedSymbol)
                }
                index += 1
                continue
            }
            seenSymbols.insert(validatedSymbol)
            
            // Parse shares (required)
            guard let shares = Double(sharesString), shares > 0 else {
                if !configuration.allowPartialParsing {
                    throw MDParserError.invalidNumericValue(field: "shares", value: sharesString)
                }
                index += 1
                continue
            }
            
            // Parse optional fields using safe optional binding
            let name: String? = {
                guard let col = nameCol, cells.count > col else { return nil }
                let value = cells[col]
                return value.isEmpty ? nil : value
            }()
            
            let assetType: AssetType? = {
                guard let col = typeCol, cells.count > col else { return nil }
                return parseAssetType(cells[col])
            }()
            
            let market: Market? = {
                guard let col = marketCol, cells.count > col else { return nil }
                return parseMarket(cells[col])
            }()
            
            let costBasis: Double? = {
                guard let col = costCol, cells.count > col else { return nil }
                return Double(cells[col])
            }()
            
            // Infer market from symbol if not specified
            let inferredMarket = market ?? inferMarket(from: validatedSymbol)
            
            let position = PositionConfig(
                symbol: validatedSymbol,
                name: name,
                assetType: assetType ?? configuration.defaultAssetType,
                market: inferredMarket,
                shares: shares,
                costBasis: costBasis
            )
            
            positions.append(position)
            index += 1
        }
        
        return positions
    }
    
    /// Finds column index by keywords
    func findColumnIndex(headers: [String], keywords: [String]) -> Int? {
        for (index, header) in headers.enumerated() {
            let normalizedHeader = header.lowercased().replacingOccurrences(of: " ", with: "")
            for keyword in keywords {
                if normalizedHeader.contains(keyword.lowercased()) {
                    return index
                }
            }
        }
        return nil
    }
}

// MARK: - List Parsing

private extension MDParser {
    
    /// Parses positions from list format (- SYMBOL: shares @ cost)
    func parsePositionsList(lines: [String], index: inout Int) throws -> [PositionConfig] {
        var positions: [PositionConfig] = []
        var seenSymbols: Set<String> = []
        
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            
            guard line.hasPrefix("- ") else { break }
            
            let content = String(line.dropFirst(2))
            
            // Try to parse: SYMBOL: shares @ cost or SYMBOL: shares
            do {
                let position = try parseListPosition(content)
                let normalizedSymbol = position.symbol
                
                if seenSymbols.contains(normalizedSymbol) {
                    if !configuration.allowPartialParsing {
                        throw MDParserError.duplicateSymbol(normalizedSymbol)
                    }
                } else {
                    seenSymbols.insert(normalizedSymbol)
                    positions.append(position)
                }
            } catch {
                if !configuration.allowPartialParsing {
                    throw MDParserError.invalidPositionFormat(line: line)
                }
            }
            
            index += 1
        }
        
        return positions
    }
    
    /// Parses a single position from list format
    func parseListPosition(_ content: String) throws -> PositionConfig {
        // Format: SYMBOL: shares @ cost or SYMBOL: shares
        
        // Split by colon to get symbol using safe string splitting
        let parts = content.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            throw MDParserError.invalidPositionFormat(line: content)
        }
        
        let symbolPart = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let rest = String(parts[1]).trimmingCharacters(in: .whitespaces)
        
        // Validate symbol
        guard let symbol = SymbolValidator.validate(symbolPart) else {
            throw MDParserError.invalidPositionFormat(line: "Invalid symbol: \(symbolPart)")
        }
        
        // Parse shares and cost
        var shares: Double = 0
        var costBasis: Double?
        
        // Check for "@" separator (cost)
        let restParts = rest.split(separator: "@", maxSplits: 1)
        let sharesPart = String(restParts[0]).trimmingCharacters(in: .whitespaces)
        
        if restParts.count == 2 {
            let costPart = String(restParts[1]).trimmingCharacters(in: .whitespaces)
            
            // Remove "shares" or "股" text
            let sharesClean = sharesPart
                .replacingOccurrences(of: "shares", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "股", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            guard let sharesValue = Double(sharesClean), sharesValue > 0 else {
                throw MDParserError.invalidNumericValue(field: "shares", value: sharesPart)
            }
            shares = sharesValue
            
            // Remove currency symbols
            let costClean = costPart
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "¥", with: "")
                .replacingOccurrences(of: "HK$", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            costBasis = Double(costClean)
        } else {
            // Just shares number
            let sharesClean = sharesPart
                .replacingOccurrences(of: "shares", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "股", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            guard let sharesValue = Double(sharesClean), sharesValue > 0 else {
                throw MDParserError.invalidNumericValue(field: "shares", value: rest)
            }
            shares = sharesValue
        }
        
        // Infer market from symbol
        let market = inferMarket(from: symbol)
        
        return PositionConfig(
            symbol: symbol,
            name: nil,
            assetType: configuration.defaultAssetType,
            market: market,
            shares: shares,
            costBasis: costBasis
        )
    }
}

// MARK: - Helper Methods

private extension MDParser {
    
    /// Parses a percentage string (8% or 0.08) into decimal
    /// - Parameters:
    ///   - value: The string value to parse (e.g., "8%", "0.08")
    ///   - field: Field name for error reporting
    /// - Returns: Decimal value (e.g., 0.08 for 8%)
    /// - Throws: MDParserError if value cannot be parsed
    /// - Note: Values > 1 without % suffix are rejected to avoid ambiguity
    func parsePercentageOrDecimal(_ value: String, field: String) throws -> Double {
        let cleanValue = value.trimmingCharacters(in: .whitespaces)
        
        // Check for percentage sign
        if cleanValue.hasSuffix("%") {
            let numberPart = String(cleanValue.dropLast()).trimmingCharacters(in: .whitespaces)
            guard let percentage = Double(numberPart) else {
                throw MDParserError.invalidPercentageValue(field: field, value: value)
            }
            return percentage / 100.0
        }
        
        // Try direct decimal
        guard let decimal = Double(cleanValue) else {
            throw MDParserError.invalidNumericValue(field: field, value: value)
        }
        
        // Reject values > 1 without % suffix to avoid ambiguity
        // Users must explicitly use % for percentages > 100%
        guard decimal <= 1.0 else {
            throw MDParserError.invalidPercentageValue(
                field: field,
                value: value
            )
        }
        
        return decimal
    }
    
    /// Parses asset type string
    func parseAssetType(_ value: String) -> AssetType? {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespaces)
        
        switch normalized {
        case "stock", "股票", "个股":
            return .stock
        case "fund", "基金":
            return .fund
        case "etf", "etfs":
            return .etf
        case "bond", "债券":
            return .bond
        case "cash", "现金":
            return .cash
        default:
            return nil
        }
    }
    
    /// Parses market string
    func parseMarket(_ value: String) -> Market? {
        let normalized = value.uppercased().trimmingCharacters(in: .whitespaces)
        
        switch normalized {
        case "US", "USA", "美股", "美国":
            return .us
        case "HK", "HONG KONG", "港股", "香港":
            return .hk
        case "CN", "CHINA", "A股", "中国", "SH", "SZ":
            return .cn
        default:
            return nil
        }
    }
    
    /// Infers market from symbol suffix or pattern
    /// - Parameter symbol: Stock symbol to analyze
    /// - Returns: Inferred market or default from configuration
    /// - Note: Only uses explicit patterns to avoid misclassification
    func inferMarket(from symbol: String) -> Market? {
        let upperSymbol = symbol.uppercased()
        
        // Explicit suffixes take precedence
        if upperSymbol.hasSuffix(".HK") {
            return .hk
        } else if upperSymbol.hasSuffix(".SS") || upperSymbol.hasSuffix(".SH") || 
                    upperSymbol.hasSuffix(".SZ") {
            return .cn
        } else if upperSymbol.hasSuffix(".US") {
            return .us
        }
        
        // Check for Chinese mainland stock codes (6 digits)
        // Pattern: Exactly 6 digits starting with 0, 3, or 6
        let digitsOnly = upperSymbol.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if digitsOnly.count == ChineseStockPatterns.mainlandCodeLength,
           let firstChar = digitsOnly.first {
            if ChineseStockPatterns.mainlandFirstDigits.contains(firstChar) {
                return .cn
            }
        }
        
        // For all other cases, use default market
        // Removed the 4-5 digit HK inference which was too aggressive
        return configuration.defaultMarket
    }
}
