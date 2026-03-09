#!/usr/bin/env swift

//
//  test-md-parser.swift
//  Test script for MDParser
//
//  Usage: swift Scripts/test-md-parser.swift
//

import Foundation

// MARK: - Test Result

enum TestResult {
    case passed
    case failed(String)
}

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
- 000001.SS: 1000 shares @ 15.5
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

// MARK: - State

var passedTests = 0
var failedTests = 0

// MARK: - Helper Functions

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

// MARK: - Main

print(String(repeating: "=", count: 60))
print("MDParser Test Suite")
print(String(repeating: "=", count: 60))
print()

// Test 1: Full format parsing
runTest(name: "Full Format - Portfolio Name") {
    if let name = validatePortfolioName(testFullFormat), name == "我的投资组合" {
        return .passed
    }
    return .failed("Expected '我的投资组合'")
}

// Test 2: Simple format parsing
runTest(name: "Simple Format - Portfolio Name") {
    if let name = validatePortfolioName(testSimpleFormat), name == "Simple Portfolio" {
        return .passed
    }
    return .failed("Expected 'Simple Portfolio'")
}

// Test 3: Table format detection
runTest(name: "Table Format Detection") {
    if validateTableFormat(testFullFormat) {
        return .passed
    }
    return .failed("Failed to detect table format")
}

// Test 4: List format detection
runTest(name: "List Format Detection") {
    if validateListFormat(testSimpleFormat) {
        return .passed
    }
    return .failed("Failed to detect list format")
}

// Test 5: Minimal format
runTest(name: "Minimal Format - Portfolio Name") {
    if let name = validatePortfolioName(testMinimalFormat), name == "Minimal Portfolio" {
        return .passed
    }
    return .failed("Expected 'Minimal Portfolio'")
}

// Test 6: Empty content handling
runTest(name: "Empty Content Detection") {
    if validatePortfolioName("") == nil {
        return .passed
    }
    return .failed("Should return nil for empty content")
}

// Test 7: Missing header handling
runTest(name: "Missing Header Detection") {
    let noHeader = "This is not a portfolio\nJust some text"
    if validatePortfolioName(noHeader) == nil {
        return .passed
    }
    return .failed("Should return nil when no header present")
}

// Test 8: Invalid table format
runTest(name: "Invalid Table Format") {
    if validateTableFormat(testInvalidFormat) {
        return .passed
    }
    return .failed("Should detect table even with invalid data")
}

print()
print(String(repeating: "=", count: 60))
print("Results: \(passedTests) passed, \(failedTests) failed")
print(String(repeating: "=", count: 60))

if failedTests > 0 {
    exit(1)
}
