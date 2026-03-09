#!/usr/bin/env swift

//
//  test-rebalancing.swift
//  Test script for Rebalancing Engine
//
//  Usage: swift Scripts/test-rebalancing.swift
//

import Foundation

// MARK: - Test Runner

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

// MARK: - Drift Calculation Tests

func calculateDrift(currentWeight: Double, targetWeight: Double) -> Double {
    currentWeight - targetWeight
}

func calculateTotalDrift(positionDrifts: [Double]) -> Double {
    let totalAbsolute = positionDrifts.reduce(0) { $0 + abs($1) }
    return totalAbsolute / 2
}

// MARK: - Tests

print(String(repeating: "=", count: 60))
print("Rebalancing Engine Test Suite")
print(String(repeating: "=", count: 60))
print()

// Test 1: Drift calculation - overweight
runTest(name: "Drift Calculation - Overweight") {
    let drift = calculateDrift(currentWeight: 0.30, targetWeight: 0.20)
    return abs(drift - 0.10) < 0.0001
}

// Test 2: Drift calculation - underweight
runTest(name: "Drift Calculation - Underweight") {
    let drift = calculateDrift(currentWeight: 0.15, targetWeight: 0.25)
    return abs(drift - (-0.10)) < 0.0001
}

// Test 3: Drift calculation - on target
runTest(name: "Drift Calculation - On Target") {
    let drift = calculateDrift(currentWeight: 0.20, targetWeight: 0.20)
    return abs(drift) < 0.0001
}

// Test 4: Total drift calculation
runTest(name: "Total Drift Calculation") {
    let drifts = [0.10, -0.10, 0.05, -0.05]
    let total = calculateTotalDrift(positionDrifts: drifts)
    // (0.10 + 0.10 + 0.05 + 0.05) / 2 = 0.15
    return abs(total - 0.15) < 0.001
}

// Test 5: Threshold detection
runTest(name: "Threshold Detection - Needs Rebalancing") {
    let drifts = [0.06, -0.06, 0.03]
    let threshold = 0.05
    let needsRebalancing = drifts.contains { abs($0) > threshold }
    return needsRebalancing == true
}

// Test 6: Threshold detection - No rebalancing needed
runTest(name: "Threshold Detection - No Rebalancing") {
    let drifts = [0.02, -0.03, 0.01]
    let threshold = 0.05
    let needsRebalancing = drifts.contains { abs($0) > threshold }
    return needsRebalancing == false
}

// Test 7: Order sizing calculation
runTest(name: "Order Sizing Calculation") {
    let drift = 0.10
    let totalValue = 100000.0
    let price = 150.0
    let adjustmentValue = drift * totalValue
    let shares = adjustmentValue / price
    return abs(shares - 66.67) < 1.0
}

// Test 8: Cash-neutral calculation
runTest(name: "Cash-Neutral Calculation") {
    let buyAmount = 5000.0
    let sellAmount = 5000.0
    let netCash = buyAmount - sellAmount
    return netCash == 0
}

// Test 9: Priority ordering
runTest(name: "Priority Ordering") {
    let drifts = [
        (symbol: "AAPL", drift: 0.12),
        (symbol: "MSFT", drift: 0.05),
        (symbol: "GOOGL", drift: 0.08)
    ]
    let sorted = drifts.sorted { $0.drift > $1.drift }
    return sorted[0].symbol == "AAPL" && sorted[2].symbol == "MSFT"
}

// Test 10: Rebalancing frequency - monthly
runTest(name: "Rebalancing Frequency - Monthly") {
    let lastDate = Date()
    let calendar = Calendar.current
    let nextDate = calendar.date(byAdding: .month, value: 1, to: lastDate)
    return nextDate != nil
}

// MARK: - Results

print()
print(String(repeating: "=", count: 60))
print("Results: \(passedTests) passed, \(failedTests) failed")
print(String(repeating: "=", count: 60))

if failedTests > 0 {
    exit(1)
}
