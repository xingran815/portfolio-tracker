#!/usr/bin/env swift

//
//  test-md-parser.swift
//  Test script for MDParser
//
//  Usage: swift Scripts/test-md-parser.swift
//

import Foundation

// MARK: - Test Runner

enum TestResult {
    case passed
    case failed(String)
}

var passedTests = 0
var failedTests = 0

func runTest(name: String, test: () -> TestResult) {
    print("Testing: \(name)...", terminator: " ")
    let result = test()
    switch result {
    case .passed:
        print("✅ PASSED")
        passedTests += 1
    case .failed(let message):
        print("❌ FAILED: \(message)")
        failedTests += 1
    }
}

// MARK: - Basic Structure Tests

func validatePortfolioName(_ content: String) -> String? {
    let lines = content.components(separatedBy: .newlines)
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("# ") {
            let name = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
    }
    return nil
}

func validateTableFormat(_ content: String) -> Bool {
    let lines = content.components(separatedBy: .newlines)
    var foundTable = false
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            foundTable = true
            let cells = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if cells.count >= 2 {
                return true
            }
        }
    }
    return foundTable
}

func validateListFormat(_ content: String) -> Bool {
    let lines = content.components(separatedBy: .newlines)
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") && trimmed.contains(":") {
            return true
        }
    }
    return false
}

// MARK: - Symbol Validation Tests

/// Validates a stock symbol (mirrors the implementation in MDParser)
func validateSymbol(_ symbol: String) -> String? {
    let maxSymbolLength = 20
    let allowedCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: ".-"))
    
    let trimmed = symbol.trimmingCharacters(in: .whitespaces)
    
    guard !trimmed.isEmpty, trimmed.count <= maxSymbolLength else {
        return nil
    }
    
    let symbolSet = CharacterSet(charactersIn: trimmed)
    guard allowedCharacters.isSuperset(of: symbolSet) else {
        return nil
    }
    
    return trimmed.uppercased()
}

// MARK: - Percentage Parsing Tests

/// Parses percentage string (mirrors the implementation in MDParser)
func parsePercentageOrDecimal(_ value: String) -> Double? {
    let cleanValue = value.trimmingCharacters(in: .whitespaces)
    
    if cleanValue.hasSuffix("%") {
        let numberPart = String(cleanValue.dropLast()).trimmingCharacters(in: .whitespaces)
        guard let percentage = Double(numberPart) else {
            return nil
        }
        return percentage / 100.0
    }
    
    guard let decimal = Double(cleanValue) else {
        return nil
    }
    
    // Values > 1 without % suffix are rejected
    guard decimal <= 1.0 else {
        return nil
    }
    
    return decimal
}

// MARK: - Market Inference Tests

/// Infers market from symbol (mirrors the implementation in MDParser)
func inferMarket(from symbol: String) -> String? {
    let upperSymbol = symbol.uppercased()
    
    // Explicit suffixes
    if upperSymbol.hasSuffix(".HK") {
        return "HK"
    } else if upperSymbol.hasSuffix(".SS") || upperSymbol.hasSuffix(".SH") || 
                upperSymbol.hasSuffix(".SZ") {
        return "CN"
    } else if upperSymbol.hasSuffix(".US") {
        return "US"
    }
    
    // Chinese mainland stock codes (6 digits starting with 0, 3, 6)
    let digitsOnly = upperSymbol.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    if digitsOnly.count == 6 {
        let firstDigit = digitsOnly.prefix(1)
        if firstDigit == "0" || firstDigit == "3" || firstDigit == "6" {
            return "CN"
        }
    }
    
    return nil
}

// MARK: - Main

print(String(repeating: "=", count: 60))
print("MDParser Test Suite")
print(String(repeating: "=", count: 60))
print()

// MARK: - Test Data

let testFullFormat = """
# 我的投资组合
- 风险偏好: moderate
- 预期收益: 8%
- 最大回撤: 15%
- 调仓频率: quarterly

## 目标配置
| 代码 | 比例 |
| AAPL | 40% |
| MSFT | 35% |
| GOOGL | 25% |

## 持仓
| 代码 | 名称 | 类型 | 市场 | 数量 | 成本 |
| AAPL | Apple | stock | US | 100 | 150.0 |
| MSFT | Microsoft | stock | US | 50 | 300.0 |
| 0700.HK | Tencent | stock | HK | 200 | 380.5 |
"""

let testSimpleFormat = """
# Simple Portfolio
- riskProfile: conservative

## Positions
- AAPL: 100 shares @ $150.0
- MSFT: 50 shares @ $300.0
- 000001.SH: 1000 shares @ 15.5
"""

let testMinimalFormat = """
# Minimal Portfolio

## 持仓
| 代码 | 数量 |
| AAPL | 100 |
| TSLA | 50 |
"""

let testInvalidFormat = """
# Invalid Test

## 持仓
| 代码 | 数量 |
| AAPL | invalid |
"""

// MARK: - Structure Tests

runTest(name: "Full Format - Portfolio Name") {
    if let name = validatePortfolioName(testFullFormat), name == "我的投资组合" {
        return .passed
    }
    return .failed("Expected '我的投资组合'")
}

runTest(name: "Simple Format - Portfolio Name") {
    if let name = validatePortfolioName(testSimpleFormat), name == "Simple Portfolio" {
        return .passed
    }
    return .failed("Expected 'Simple Portfolio'")
}

runTest(name: "Table Format Detection") {
    if validateTableFormat(testFullFormat) {
        return .passed
    }
    return .failed("Failed to detect table format")
}

runTest(name: "List Format Detection") {
    if validateListFormat(testSimpleFormat) {
        return .passed
    }
    return .failed("Failed to detect list format")
}

runTest(name: "Minimal Format - Portfolio Name") {
    if let name = validatePortfolioName(testMinimalFormat), name == "Minimal Portfolio" {
        return .passed
    }
    return .failed("Expected 'Minimal Portfolio'")
}

runTest(name: "Empty Content Detection") {
    if validatePortfolioName("") == nil {
        return .passed
    }
    return .failed("Should return nil for empty content")
}

runTest(name: "Missing Header Detection") {
    let noHeader = "This is not a portfolio\nJust some text"
    if validatePortfolioName(noHeader) == nil {
        return .passed
    }
    return .failed("Should return nil when no header present")
}

runTest(name: "Invalid Table Format") {
    if validateTableFormat(testInvalidFormat) {
        return .passed
    }
    return .failed("Should detect table even with invalid data")
}

// MARK: - Symbol Validation Tests

runTest(name: "Symbol Validation - Valid AAPL") {
    if validateSymbol("AAPL") == "AAPL" {
        return .passed
    }
    return .failed("Should accept AAPL")
}

runTest(name: "Symbol Validation - Valid with suffix") {
    if validateSymbol("0700.HK") == "0700.HK" {
        return .passed
    }
    return .failed("Should accept 0700.HK")
}

runTest(name: "Symbol Validation - Reject special chars") {
    if validateSymbol("BRK.A!") == nil {
        return .passed
    }
    return .failed("Should reject special characters")
}

runTest(name: "Symbol Validation - Trims whitespace") {
    if validateSymbol("  AAPL  ") == "AAPL" {
        return .passed
    }
    return .failed("Should trim whitespace")
}

runTest(name: "Symbol Validation - Reject too long") {
    if validateSymbol(String(repeating: "A", count: 25)) == nil {
        return .passed
    }
    return .failed("Should reject symbols > 20 chars")
}

// MARK: - Percentage Parsing Tests

runTest(name: "Percentage - Valid percent format") {
    if parsePercentageOrDecimal("8%") == 0.08 {
        return .passed
    }
    return .failed("Should parse 8% as 0.08")
}

runTest(name: "Percentage - Valid decimal format") {
    if parsePercentageOrDecimal("0.08") == 0.08 {
        return .passed
    }
    return .failed("Should parse 0.08 as 0.08")
}

runTest(name: "Percentage - Reject value > 1 without %") {
    if parsePercentageOrDecimal("8") == nil {
        return .passed
    }
    return .failed("Should reject 8 without % (ambiguous)")
}

runTest(name: "Percentage - Accept 100%") {
    if parsePercentageOrDecimal("100%") == 1.0 {
        return .passed
    }
    return .failed("Should parse 100% as 1.0")
}

runTest(name: "Percentage - Reject invalid") {
    if parsePercentageOrDecimal("abc") == nil {
        return .passed
    }
    return .failed("Should reject invalid input")
}

// MARK: - Market Inference Tests

runTest(name: "Market Inference - .HK suffix") {
    if inferMarket(from: "0700.HK") == "HK" {
        return .passed
    }
    return .failed("Should infer HK from .HK suffix")
}

runTest(name: "Market Inference - .SH suffix") {
    if inferMarket(from: "000001.SH") == "CN" {
        return .passed
    }
    return .failed("Should infer CN from .SH suffix")
}

runTest(name: "Market Inference - .SZ suffix") {
    if inferMarket(from: "000001.SZ") == "CN" {
        return .passed
    }
    return .failed("Should infer CN from .SZ suffix")
}

runTest(name: "Market Inference - 6-digit mainland code") {
    if inferMarket(from: "000001") == "CN" {
        return .passed
    }
    return .failed("Should infer CN from 6-digit code starting with 0")
}

runTest(name: "Market Inference - 6-digit code starting with 3") {
    if inferMarket(from: "300001") == "CN" {
        return .passed
    }
    return .failed("Should infer CN from 6-digit code starting with 3")
}

runTest(name: "Market Inference - 6-digit code starting with 6") {
    if inferMarket(from: "600001") == "CN" {
        return .passed
    }
    return .failed("Should infer CN from 6-digit code starting with 6")
}

runTest(name: "Market Inference - US symbol no pattern") {
    if inferMarket(from: "AAPL") == nil {
        return .passed
    }
    return .failed("Should not infer market for US symbols without suffix")
}

runTest(name: "Market Inference - No 4-5 digit HK inference") {
    // Previously this would incorrectly infer HK
    if inferMarket(from: "2020") == nil {
        return .passed
    }
    return .failed("Should not infer HK from 4-digit number")
}

// MARK: - Results

print()
print(String(repeating: "=", count: 60))
print("Results: \(passedTests) passed, \(failedTests) failed")
print(String(repeating: "=", count: 60))

if failedTests > 0 {
    exit(1)
}
