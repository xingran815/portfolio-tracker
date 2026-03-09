//
//  MDParser.swift
//  portfolio_tracker
//
//  Markdown portfolio configuration parser implementation
//

import Foundation

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
            if line.hasPrefix("##") || line.hasPrefix("|") || line.hasPrefix("-") {
                break
            }
            
            // Parse key-value pair
            if line.hasPrefix("- ") {
                let content = String(line.dropFirst(2))
                if let separatorIndex = content.firstIndex(of: ":") {
                    let key = String(content[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(content[content.index(after: separatorIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                    
                    try parseMetadataKey(key: key, value: value, metadata: &metadata)
                }
            }
            
            index += 1
        }
        
        return metadata
    }
    
    /// Parses a single metadata key-value pair
    func parseMetadataKey(key: String, value: String, metadata: inout ParsedMetadata) throws {
        let normalizedKey = key.lowercased().replacingOccurrences(of: " ", with: "")
        
        switch normalizedKey {
        case "风险偏好", "riskprofile", "risk":
            guard let profile = RiskProfile(rawValue: value.lowercased()) else {
                throw MDParserError.invalidRiskProfile(value)
            }
            metadata.riskProfile = profile
            
        case "预期收益", "expectedreturn", "return", "目标收益":
            metadata.expectedReturn = try parsePercentageOrDecimal(value, field: "expectedReturn")
            
        case "最大回撤", "maxdrawdown", "drawdown":
            metadata.maxDrawdown = try parsePercentageOrDecimal(value, field: "maxDrawdown")
            
        case "调仓频率", "rebalancingfrequency", "frequency", "再平衡频率":
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
        
        guard let symbolCol = headers.firstIndex(where: { 
            $0.lowercased() == "代码" || $0.lowercased() == "symbol" || $0.lowercased() == "股票"
        }),
              let ratioCol = headers.firstIndex(where: {
                  $0.lowercased() == "比例" || $0.lowercased() == "ratio" || 
                  $0.lowercased() == "percentage" || $0.lowercased() == "占比"
              }) else {
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
            
            if let ratio = try? parsePercentageOrDecimal(ratioString, field: "targetAllocation") {
                allocation[symbol] = ratio
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
        
        // Map column indices
        let symbolCol = findColumnIndex(headers: headers, keywords: ["代码", "symbol", "股票", "代码"])
        let nameCol = findColumnIndex(headers: headers, keywords: ["名称", "name", "股票名称"])
        let typeCol = findColumnIndex(headers: headers, keywords: ["类型", "type", "assettype"])
        let marketCol = findColumnIndex(headers: headers, keywords: ["市场", "market", "交易所"])
        let sharesCol = findColumnIndex(headers: headers, keywords: ["数量", "shares", "股数", "持仓"])
        let costCol = findColumnIndex(headers: headers, keywords: ["成本", "cost", "costbasis", "买入价"])
        
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
            
            guard !symbol.isEmpty else {
                index += 1
                continue
            }
            
            // Check for duplicates
            let normalizedSymbol = symbol.uppercased()
            if seenSymbols.contains(normalizedSymbol) {
                if !configuration.allowPartialParsing {
                    throw MDParserError.duplicateSymbol(symbol)
                }
                index += 1
                continue
            }
            seenSymbols.insert(normalizedSymbol)
            
            // Parse shares (required)
            guard let shares = Double(sharesString), shares > 0 else {
                if !configuration.allowPartialParsing {
                    throw MDParserError.invalidNumericValue(field: "shares", value: sharesString)
                }
                index += 1
                continue
            }
            
            // Parse optional fields
            let name = nameCol != nil && cells.count > nameCol! ? cells[nameCol!] : nil
            let assetType = typeCol != nil && cells.count > typeCol! ? parseAssetType(cells[typeCol!]) : nil
            let market = marketCol != nil && cells.count > marketCol! ? parseMarket(cells[marketCol!]) : nil
            let costBasis = costCol != nil && cells.count > costCol! ? Double(cells[costCol!]) : nil
            
            // Infer market from symbol if not specified
            let inferredMarket = market ?? inferMarket(from: symbol)
            
            let position = PositionConfig(
                symbol: normalizedSymbol,
                name: name?.isEmpty == false ? name : nil,
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
            if let position = try? parseListPosition(content) {
                let normalizedSymbol = position.symbol.uppercased()
                
                if seenSymbols.contains(normalizedSymbol) {
                    if !configuration.allowPartialParsing {
                        throw MDParserError.duplicateSymbol(position.symbol)
                    }
                } else {
                    seenSymbols.insert(normalizedSymbol)
                    positions.append(position)
                }
            } else if !configuration.allowPartialParsing {
                throw MDParserError.invalidPositionFormat(line: line)
            }
            
            index += 1
        }
        
        return positions
    }
    
    /// Parses a single position from list format
    func parseListPosition(_ content: String) throws -> PositionConfig {
        // Format: SYMBOL: shares @ cost or SYMBOL: shares
        
        // Split by colon to get symbol
        guard let colonIndex = content.firstIndex(of: ":") else {
            throw MDParserError.invalidPositionFormat(line: content)
        }
        
        let symbol = String(content[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let rest = String(content[content.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespaces)
        
        // Parse shares and cost
        var shares: Double = 0
        var costBasis: Double?
        
        // Check for "@" separator (cost)
        if let atIndex = rest.firstIndex(of: "@") {
            let sharesPart = String(rest[..<atIndex]).trimmingCharacters(in: .whitespaces)
            let costPart = String(rest[rest.index(after: atIndex)...])
                .trimmingCharacters(in: .whitespaces)
            
            // Remove "shares" or "股" text
            let sharesClean = sharesPart.replacingOccurrences(of: "shares", with: "")
                .replacingOccurrences(of: "股", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            guard let s = Double(sharesClean), s > 0 else {
                throw MDParserError.invalidNumericValue(field: "shares", value: sharesPart)
            }
            shares = s
            
            // Remove currency symbols
            let costClean = costPart.replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "¥", with: "")
                .replacingOccurrences(of: "HK$", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            costBasis = Double(costClean)
        } else {
            // Just shares number
            let sharesClean = rest.replacingOccurrences(of: "shares", with: "")
                .replacingOccurrences(of: "股", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            guard let s = Double(sharesClean), s > 0 else {
                throw MDParserError.invalidNumericValue(field: "shares", value: rest)
            }
            shares = s
        }
        
        // Infer market from symbol
        let market = inferMarket(from: symbol)
        
        return PositionConfig(
            symbol: symbol.uppercased(),
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
        
        // If value > 1, assume it's a percentage (e.g., 8 means 8%)
        if decimal > 1.0 {
            return decimal / 100.0
        }
        
        return decimal
    }
    
    /// Parses asset type string
    func parseAssetType(_ value: String) -> AssetType? {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespaces)
        
        switch normalized {
        case "stock", "股票", "个股":
            return .stock
        case "fund", "基金", " mutual fund":
            return .fund
        case "etf", "etfs":
            return .etf
        case "bond", "债券":
            return .bond
        case "cash", "现金", "cash equivalent":
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
    
    /// Infers market from symbol suffix
    func inferMarket(from symbol: String) -> Market? {
        let upperSymbol = symbol.uppercased()
        
        if upperSymbol.hasSuffix(".HK") {
            return .hk
        } else if upperSymbol.hasSuffix(".SS") || upperSymbol.hasSuffix(".SZ") {
            return .cn
        } else if upperSymbol.hasSuffix(".US") {
            return .us
        }
        
        // Chinese stock codes (6 digits starting with 0, 3, 6)
        let digitsOnly = upperSymbol.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if digitsOnly.count == 6 {
            let firstDigit = digitsOnly.prefix(1)
            if firstDigit == "0" || firstDigit == "3" || firstDigit == "6" {
                return .cn
            }
        }
        
        // Hong Kong stock codes (4-5 digits)
        if digitsOnly.count >= 4 && digitsOnly.count <= 5 {
            return .hk
        }
        
        return configuration.defaultMarket
    }
}
