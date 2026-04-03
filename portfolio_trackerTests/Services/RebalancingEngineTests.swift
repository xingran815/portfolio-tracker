//
//  RebalancingEngineTests.swift
//  portfolio_trackerTests
//
//  Unit tests for Rebalancing Engine
//

import XCTest
import CoreData
@testable import portfolio_tracker

// MARK: - DriftAnalyzer Tests

@MainActor
final class DriftAnalyzerTests: XCTestCase {
    
    var analyzer: DriftAnalyzer!
    
    override func setUp() {
        super.setUp()
        analyzer = DriftAnalyzer(threshold: 0.05)
    }
    
    override func tearDown() {
        analyzer = nil
        super.tearDown()
    }
    
    // MARK: - Basic Drift Calculation
    
    func testDriftOverweight() throws {
        // 30% current, 20% target = 10% drift (overweight)
        // Need to include other assets to make allocation sum to 1.0
        let position = PositionData(symbol: "AAPL", currentValue: 3000)
        let cashPosition = PositionData(symbol: "CASH", currentValue: 7000)
        let analysis = try analyzer.analyze(
            positions: [position, cashPosition],
            targetAllocation: ["AAPL": 0.20, "CASH": 0.80],
            totalValue: 10000
        )
        
        XCTAssertEqual(analysis.positions.count, 2)
        let aaplDrift = analysis.positions.first { $0.symbol == "AAPL" }
        XCTAssertNotNil(aaplDrift)
        XCTAssertEqual(aaplDrift!.drift, 0.10, accuracy: 0.001)
        XCTAssertTrue(aaplDrift!.isOverweight)
        XCTAssertFalse(aaplDrift!.isUnderweight)
    }
    
    func testDriftUnderweight() throws {
        // 15% current, 25% target = -10% drift (underweight)
        let position = PositionData(symbol: "AAPL", currentValue: 1500)
        let cashPosition = PositionData(symbol: "CASH", currentValue: 8500)
        let analysis = try analyzer.analyze(
            positions: [position, cashPosition],
            targetAllocation: ["AAPL": 0.25, "CASH": 0.75],
            totalValue: 10000
        )
        
        let aaplDrift = analysis.positions.first { $0.symbol == "AAPL" }
        XCTAssertNotNil(aaplDrift)
        XCTAssertEqual(aaplDrift!.drift, -0.10, accuracy: 0.001)
        XCTAssertTrue(aaplDrift!.isUnderweight)
        XCTAssertFalse(aaplDrift!.isOverweight)
    }
    
    func testDriftOnTarget() throws {
        // 20% current, 20% target = 0% drift
        let position = PositionData(symbol: "AAPL", currentValue: 2000)
        let cashPosition = PositionData(symbol: "CASH", currentValue: 8000)
        let analysis = try analyzer.analyze(
            positions: [position, cashPosition],
            targetAllocation: ["AAPL": 0.20, "CASH": 0.80],
            totalValue: 10000
        )
        
        let aaplDrift = analysis.positions.first { $0.symbol == "AAPL" }
        XCTAssertNotNil(aaplDrift)
        XCTAssertEqual(aaplDrift!.drift, 0.0, accuracy: 0.001)
        XCTAssertFalse(aaplDrift!.isOverweight)
        XCTAssertFalse(aaplDrift!.isUnderweight)
    }
    
    // MARK: - Threshold Detection
    
    func testNeedsRebalancingWhenThresholdExceeded() throws {
        // 35% current, 20% target = 15% drift (overweight)
        let position = PositionData(symbol: "AAPL", currentValue: 3500)
        let cashPosition = PositionData(symbol: "CASH", currentValue: 6500)
        let analysis = try analyzer.analyze(
            positions: [position, cashPosition],
            targetAllocation: ["AAPL": 0.20, "CASH": 0.80],
            totalValue: 10000
        )
        
        XCTAssertTrue(analysis.needsRebalancing)
        XCTAssertTrue(analysis.totalDrift > 0.05)
    }
    
    func testNoRebalancingWhenWithinThreshold() throws {
        // 22% current, 20% target = 2% drift (within threshold)
        let position = PositionData(symbol: "AAPL", currentValue: 2200)
        let cashPosition = PositionData(symbol: "CASH", currentValue: 7800)
        let analysis = try analyzer.analyze(
            positions: [position, cashPosition],
            targetAllocation: ["AAPL": 0.20, "CASH": 0.80],
            totalValue: 10000
        )
        
        XCTAssertFalse(analysis.needsRebalancing)
    }
    
    // MARK: - Multiple Positions
    
    func testMultiplePositionsDrift() throws {
        let positions = [
            PositionData(symbol: "AAPL", currentValue: 4000), // 40% current, 30% target
            PositionData(symbol: "MSFT", currentValue: 2000), // 20% current, 30% target
            PositionData(symbol: "GOOGL", currentValue: 4000) // 40% current, 40% target
        ]
        
        let analysis = try analyzer.analyze(
            positions: positions,
            targetAllocation: ["AAPL": 0.30, "MSFT": 0.30, "GOOGL": 0.40],
            totalValue: 10000
        )
        
        XCTAssertEqual(analysis.positions.count, 3)
        
        let aaplDrift = analysis.positions.first { $0.symbol == "AAPL" }
        let msftDrift = analysis.positions.first { $0.symbol == "MSFT" }
        let googlDrift = analysis.positions.first { $0.symbol == "GOOGL" }
        
        XCTAssertNotNil(aaplDrift)
        XCTAssertNotNil(msftDrift)
        XCTAssertNotNil(googlDrift)
        
        XCTAssertEqual(aaplDrift!.drift, 0.10, accuracy: 0.001)
        XCTAssertEqual(msftDrift!.drift, -0.10, accuracy: 0.001)
        XCTAssertEqual(googlDrift!.drift, 0.0, accuracy: 0.001)
    }
    
    // MARK: - Missing Positions
    
    func testMissingTargetPositionDetection() throws {
        let positions = [
            PositionData(symbol: "AAPL", currentValue: 5000)
        ]
        
        let analysis = try analyzer.analyze(
            positions: positions,
            targetAllocation: ["AAPL": 0.50, "MSFT": 0.50], // MSFT missing
            totalValue: 10000
        )
        
        let msftDrift = analysis.positions.first { $0.symbol == "MSFT" }
        XCTAssertNotNil(msftDrift)
        XCTAssertEqual(msftDrift!.currentValue, 0)
        XCTAssertEqual(msftDrift!.targetWeight, 0.50)
        XCTAssertEqual(msftDrift!.drift, -0.50, accuracy: 0.001)
    }
    
    // MARK: - Allocation Normalization
    
    func testAllocationNormalization() throws {
        // Target sums to 2.0 (needs normalization)
        let positions = [
            PositionData(symbol: "AAPL", currentValue: 5000)
        ]
        
        let analysis = try analyzer.analyze(
            positions: positions,
            targetAllocation: ["AAPL": 1.0], // Will be normalized to 1.0
            totalValue: 10000
        )
        
        XCTAssertEqual(analysis.positions[0].targetWeight, 1.0)
    }
    
    // MARK: - Error Handling
    
    func testEmptyPositionsThrowsError() {
        let emptyPositions: [PositionData] = []
        XCTAssertThrowsError(try analyzer.analyze(
            positions: emptyPositions,
            targetAllocation: ["AAPL": 0.5],
            totalValue: 10000
        )) { error in
            XCTAssertTrue(error is DriftAnalysisError)
            if let driftError = error as? DriftAnalysisError {
                XCTAssertEqual(driftError, DriftAnalysisError.noPositions)
            }
        }
    }
    
    func testEmptyTargetAllocationThrowsError() {
        let positions = [PositionData(symbol: "AAPL", currentValue: 5000)]
        
        XCTAssertThrowsError(try analyzer.analyze(
            positions: positions,
            targetAllocation: [:],
            totalValue: 10000
        )) { error in
            XCTAssertTrue(error is DriftAnalysisError)
        }
    }
    
    func testZeroTotalValueThrowsError() {
        let positions = [PositionData(symbol: "AAPL", currentValue: 0)]
        
        XCTAssertThrowsError(try analyzer.analyze(
            positions: positions,
            targetAllocation: ["AAPL": 1.0],
            totalValue: 0
        )) { error in
            XCTAssertTrue(error is DriftAnalysisError)
        }
    }
    
    // MARK: - Convenience Methods
    
    func testSignificantDriftsFiltering() throws {
        // Total value = 10000, threshold = 5%
        // AAPL: 45% current, 30% target = 15% drift (significant)
        // MSFT: 21% current, 20% target = 1% drift (not significant)
        // CASH: 34% current, 50% target = -16% drift (significant)
        let positions = [
            PositionData(symbol: "AAPL", currentValue: 4500),
            PositionData(symbol: "MSFT", currentValue: 2100),
            PositionData(symbol: "CASH", currentValue: 3400)
        ]
        
        let analysis = try analyzer.analyze(
            positions: positions,
            targetAllocation: ["AAPL": 0.30, "MSFT": 0.20, "CASH": 0.50],
            totalValue: 10000
        )
        
        let significantDrifts = analysis.significantDrifts
        // AAPL has 15% drift (significant)
        // CASH has -16% drift (significant)
        // MSFT has 1% drift (not significant)
        XCTAssertEqual(significantDrifts.count, 2)
        XCTAssertTrue(significantDrifts.contains { $0.symbol == "AAPL" })
    }
}

// MARK: - RebalancingEngine Tests

@MainActor
final class RebalancingEngineTests: XCTestCase {
    
    var engine: RebalancingEngine!
    
    override func setUp() async throws {
        try await super.setUp()
        engine = RebalancingEngine(configuration: .default)
    }
    
    override func tearDown() async throws {
        engine = nil
        try await super.tearDown()
    }
    
    // MARK: - Plan Generation
    
    func testGeneratePlanWithDrift() async throws {
        // Portfolio: 100% AAPL, target: 50% AAPL, 50% CASH
        // Should suggest selling AAPL
        let snapshot = PortfolioSnapshot(
            id: UUID(),
            name: "Test Portfolio",
            positions: [
                PositionSnapshot(
                    id: UUID(),
                    symbol: "AAPL",
                    name: "Apple",
                    shares: 100,
                    costBasis: 150,
                    currentPrice: 200,
                    currentValue: 20000,
                    profitLoss: 5000,
                    profitLossPercentage: 0.33,
                    assetType: .stock,
                    market: .us,
                    lastUpdated: Date()
                )
            ],
            targetAllocation: ["AAPL": 0.50, "CASH": 0.50],  // AAPL is 100%, target 50%
            totalValue: 20000,
            rebalancingFrequency: .quarterly,
            lastRebalancedAt: nil
        )
        
        // 100% in AAPL, target is 50% - should suggest selling
        let plan = try await engine.generatePlan(from: snapshot, availableCash: 10000)
        
        XCTAssertFalse(plan.orders.isEmpty)
        XCTAssertEqual(plan.portfolioName, "Test Portfolio")
        XCTAssertNotNil(plan.driftAnalysis)
    }
    
    func testNoRebalancingWhenNoSignificantDrift() async {
        // Portfolio: 50% AAPL, target: 50% AAPL, 50% CASH (normalized to 50/50)
        let snapshot = PortfolioSnapshot(
            id: UUID(),
            name: "Test Portfolio",
            positions: [
                PositionSnapshot(
                    id: UUID(),
                    symbol: "AAPL",
                    name: "Apple",
                    shares: 50,
                    costBasis: 100,
                    currentPrice: 200,
                    currentValue: 10000,
                    profitLoss: 5000,
                    profitLossPercentage: 0.50,
                    assetType: .stock,
                    market: .us,
                    lastUpdated: Date()
                ),
                PositionSnapshot(
                    id: UUID(),
                    symbol: "CASH",
                    name: "Cash",
                    shares: 10000,
                    costBasis: 1,
                    currentPrice: 1,
                    currentValue: 10000,
                    profitLoss: 0,
                    profitLossPercentage: 0,
                    assetType: .cash,
                    market: .us,
                    lastUpdated: Date()
                )
            ],
            targetAllocation: ["AAPL": 0.50, "CASH": 0.50],
            totalValue: 20000,
            rebalancingFrequency: .quarterly,
            lastRebalancedAt: nil
        )
        
        do {
            _ = try await engine.generatePlan(from: snapshot, availableCash: 10000)
            XCTFail("Should throw noSignificantDrift error")
        } catch let error as RebalancingError {
            XCTAssertEqual(error, RebalancingError.noSignificantDrift)
        } catch {
            XCTFail("Unexpected error type")
        }
    }
    
    func testInsufficientCashError() async {
        let snapshot = PortfolioSnapshot(
            id: UUID(),
            name: "Test Portfolio",
            positions: [],
            targetAllocation: ["AAPL": 1.0],
            totalValue: 0, // Invalid - will trigger validation error
            rebalancingFrequency: .quarterly,
            lastRebalancedAt: nil
        )
        
        do {
            _ = try await engine.generatePlan(from: snapshot, availableCash: 0)
            XCTFail("Should throw invalidSnapshot error")
        } catch let error as RebalancingError {
            if case .invalidSnapshot = error {
                // Expected
            } else {
                XCTFail("Expected invalidSnapshot error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }
    
    // MARK: - Schedule Calculation
    
    func testNextRebalancingDateMonthly() async {
        let baseDate = Date()
        let nextDate = await engine.nextRebalancingDate(
            lastRebalanceDate: baseDate,
            frequency: .monthly
        )
        
        let calendar = Calendar.current
        guard let expectedDate = calendar.date(byAdding: .month, value: 1, to: baseDate) else {
            XCTFail("Failed to create expected date")
            return
        }
        
        XCTAssertEqual(
            calendar.startOfDay(for: nextDate),
            calendar.startOfDay(for: expectedDate)
        )
    }
    
    func testNextRebalancingDateQuarterly() async {
        let baseDate = Date()
        let nextDate = await engine.nextRebalancingDate(
            lastRebalanceDate: baseDate,
            frequency: .quarterly
        )
        
        let calendar = Calendar.current
        guard let expectedDate = calendar.date(byAdding: .month, value: 3, to: baseDate) else {
            XCTFail("Failed to create expected date")
            return
        }
        
        XCTAssertEqual(
            calendar.startOfDay(for: nextDate),
            calendar.startOfDay(for: expectedDate)
        )
    }
    
    func testIsRebalancingOverdue() async {
        guard let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: Date()) else {
            XCTFail("Failed to create two months ago date")
            return
        }
        
        let isOverdue = await engine.isRebalancingOverdue(
            lastRebalanceDate: twoMonthsAgo,
            frequency: .monthly
        )
        
        XCTAssertTrue(isOverdue)
    }
    
    func testIsNotRebalancingOverdue() async {
        guard let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else {
            XCTFail("Failed to create one week ago date")
            return
        }
        
        let isOverdue = await engine.isRebalancingOverdue(
            lastRebalanceDate: oneWeekAgo,
            frequency: .monthly
        )
        
        XCTAssertFalse(isOverdue)
    }
    
    func testOverdueWhenNeverRebalanced() async {
        let isOverdue = await engine.isRebalancingOverdue(
            lastRebalanceDate: nil,
            frequency: .quarterly
        )
        
        XCTAssertTrue(isOverdue)
    }
}

// MARK: - PositionData Helper

/// Test helper struct conforming to PositionProtocol
struct PositionData: PositionProtocol {
    let symbol: String?
    let currentValue: Double?
    
    init(symbol: String, currentValue: Double) {
        self.symbol = symbol
        self.currentValue = currentValue
    }
}

// MARK: - Error Equality Extensions

extension RebalancingError: @retroactive Equatable {
    public static func == (lhs: RebalancingError, rhs: RebalancingError) -> Bool {
        switch (lhs, rhs) {
        case (.noSignificantDrift, .noSignificantDrift):
            return true
        case (.invalidSnapshot, .invalidSnapshot):
            return true
        case (.insufficientCash, .insufficientCash):
            return true
        default:
            return false
        }
    }
}
