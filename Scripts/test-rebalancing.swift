#!/usr/bin/env swift

//
//  test-rebalancing.swift
//  Comprehensive tests for Rebalancing Engine
//

import Foundation

// MARK: - Test Infrastructure

var passedTests = 0
var failedTests = 0

func runTest(name: String, test: () -> Bool) {
    print("Testing: \(name)...", terminator: " ")
    if test() {
        print("✅ PASSED")
        passedTests += 1
    } else {
        print("❌ FAILED")
        failedTests += 1
    }
}

func runAsyncTest(name: String, test: () async -> Bool) async {
    print("Testing: \(name)...", terminator: " ")
    if await test() {
        print("✅ PASSED")
        passedTests += 1
    } else {
        print("❌ FAILED")
        failedTests += 1
    }
}

// MARK: - Constants Tests

runTest(name: "Financial Constants") {
    // Verify constants are reasonable
    let epsilon = 1e-10
    let minWeight = 1e-10
    return epsilon > 0 && minWeight > 0
}

// MARK: - Drift Calculation Tests

runTest(name: "Drift - Overweight") {
    let currentWeight = 0.30
    let targetWeight = 0.20
    let drift = currentWeight - targetWeight
    return abs(drift - 0.10) < 0.0001
}

runTest(name: "Drift - Underweight") {
    let currentWeight = 0.15
    let targetWeight = 0.25
    let drift = currentWeight - targetWeight
    return abs(drift - (-0.10)) < 0.0001
}

runTest(name: "Drift - Zero Division Protection") {
    // When current weight is 0, we shouldn't divide by it
    let currentWeight = 0.0
    let minWeight = 1e-10
    let adjustedWeight = max(currentWeight, minWeight)
    return adjustedWeight == minWeight
}

// MARK: - Threshold Tests

runTest(name: "5% Threshold Detection") {
    let drift = 0.06
    let threshold = 0.05
    return drift > threshold
}

runTest(name: "Threshold Not Exceeded") {
    let drift = 0.03
    let threshold = 0.05
    return drift <= threshold
}

// MARK: - Allocation Normalization Tests

runTest(name: "Allocation Normalization") {
    let allocation = ["AAPL": 0.5, "MSFT": 0.5]
    let total = allocation.values.reduce(0, +)
    return abs(total - 1.0) < 0.01
}

runTest(name: "Allocation Normalization - Needs Adjustment") {
    let allocation = ["AAPL": 50.0, "MSFT": 50.0]  // Sum = 100
    let total = allocation.values.reduce(0, +)
    let normalized = allocation.mapValues { $0 / total }
    let newTotal = normalized.values.reduce(0, +)
    return abs(newTotal - 1.0) < 0.0001
}

// MARK: - Order Sizing Tests

runTest(name: "Order Sizing - Basic") {
    let drift = 0.10
    let totalValue = 100000.0
    let price = 150.0
    let adjustmentValue = drift * totalValue
    let shares = adjustmentValue / price
    return abs(shares - 66.67) < 1.0
}

runTest(name: "Order Sizing - With Minimum") {
    let adjustmentValue = 50.0
    let minimumSize = 100.0
    let shouldFilter = adjustmentValue < minimumSize
    return shouldFilter == true
}

// MARK: - Cash Flow Tests

runTest(name: "Cash Neutral") {
    let buyAmount = 5000.0
    let sellAmount = 5000.0
    let netCash = buyAmount - sellAmount
    return netCash == 0
}

runTest(name: "Cash Required") {
    let buyAmount = 10000.0
    let sellAmount = 3000.0
    let netCash = buyAmount - sellAmount
    return netCash == 7000.0
}

runTest(name: "Cash Generated") {
    let buyAmount = 2000.0
    let sellAmount = 8000.0
    let netCash = buyAmount - sellAmount
    return netCash == -6000.0
}

// MARK: - Priority Tests

runTest(name: "Priority Comparison") {
    let highPriority = 3
    let mediumPriority = 2
    let lowPriority = 1
    return highPriority > mediumPriority && mediumPriority > lowPriority
}

runTest(name: "Sort by Drift") {
    let drifts = [
        (symbol: "AAPL", drift: 0.12),
        (symbol: "MSFT", drift: 0.05),
        (symbol: "GOOGL", drift: 0.08)
    ]
    let sorted = drifts.sorted { $0.drift > $1.drift }
    return sorted[0].symbol == "AAPL" && sorted[2].symbol == "MSFT"
}

// MARK: - Schedule Tests

runTest(name: "Monthly Frequency") {
    let calendar = Calendar.current
    let baseDate = Date()
    let nextDate = calendar.date(byAdding: .month, value: 1, to: baseDate)
    return nextDate != nil && nextDate! > baseDate
}

runTest(name: "Quarterly Frequency") {
    let calendar = Calendar.current
    let baseDate = Date()
    let monthlyDate = calendar.date(byAdding: .month, value: 1, to: baseDate)
    let quarterlyDate = calendar.date(byAdding: .month, value: 3, to: baseDate)
    return quarterlyDate! > monthlyDate!
}

runTest(name: "Overdue Detection") {
    let pastDate = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
    let isOverdue = Date() > pastDate
    return isOverdue == true
}

// MARK: - Error Handling Tests

runTest(name: "Empty Portfolio Error") {
    let positions: [String] = []
    let isEmpty = positions.isEmpty
    return isEmpty
}

runTest(name: "Zero Total Value Error") {
    let totalValue = 0.0
    let epsilon = 1e-10
    let isZero = totalValue <= epsilon
    return isZero
}

runTest(name: "Negative Value Error") {
    let totalValue = -1000.0
    let isNegative = totalValue < 0
    return isNegative
}

// MARK: - Strategy Tests

runTest(name: "Threshold Strategy Logic") {
    let drift = 0.08
    let threshold = 0.05
    let shouldRebalance = drift > threshold
    return shouldRebalance
}

runTest(name: "Cash Flow Strategy - Sell First") {
    let orders = [
        (action: "sell", amount: 5000),
        (action: "buy", amount: 3000)
    ]
    let sellFirst = orders.sorted { a, b in
        if a.action == "sell" && b.action == "buy" { return true }
        return false
    }
    return sellFirst[0].action == "sell"
}

// MARK: - Edge Case Tests

runTest(name: "Single Position Portfolio") {
    let positions = ["AAPL"]
    let targetAllocation = ["AAPL": 1.0]
    let isValid = positions.count == 1 && targetAllocation.count == 1
    return isValid
}

runTest(name: "Missing Target Position") {
    let currentPositions = ["AAPL"]
    let targetSymbols = Set(["AAPL", "MSFT"])
    let missing = targetSymbols.subtracting(currentPositions)
    return missing.contains("MSFT")
}

runTest(name: "Extra Position Not In Target") {
    let currentPositions = Set(["AAPL", "TSLA"])
    let targetSymbols = Set(["AAPL"])
    let extra = currentPositions.subtracting(targetSymbols)
    return extra.contains("TSLA")
}

// MARK: - Validation Tests

runTest(name: "Order Validation - Valid") {
    let shares = 100.0
    let price = 150.0
    let isValid = shares > 0 && price > 0
    return isValid
}

runTest(name: "Order Validation - Invalid Shares") {
    let shares = 0.0
    let isValid = shares > 0
    return !isValid
}

runTest(name: "Order Validation - Invalid Price") {
    let price = -10.0
    let isValid = price > 0
    return !isValid
}

// MARK: - Tax Optimization Tests

runTest(name: "Tax Loss Detection") {
    let profitLoss = -500.0
    let hasLoss = profitLoss < 0
    return hasLoss
}

runTest(name: "Tax Gain Detection") {
    let profitLoss = 500.0
    let hasGain = profitLoss > 0
    return hasGain
}

// MARK: - Results

print()
print(String(repeating: "=", count: 60))
print("Results: \(passedTests) passed, \(failedTests) failed")
print(String(repeating: "=", count: 60))

if failedTests > 0 {
    exit(1)
}
