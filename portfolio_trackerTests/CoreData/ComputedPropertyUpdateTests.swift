//
//  ComputedPropertyUpdateTests.swift
//  portfolio_trackerTests
//
//  Tests for computed property updates when related data changes
//

import XCTest
import CoreData
@testable import portfolio_tracker

@MainActor
final class ComputedPropertyUpdateTests: XCTestCase {
    
    var persistenceController: PersistenceController!
    var viewContext: NSManagedObjectContext!
    
    override func setUp() async throws {
        try await super.setUp()
        
        persistenceController = PersistenceController(inMemory: true)
        viewContext = persistenceController.viewContext
    }
    
    override func tearDown() async throws {
        persistenceController = nil
        viewContext = nil
        try await super.tearDown()
    }
    
    // MARK: - Portfolio Total Value Tests
    
    func testPortfolioTotalValue_updatesAfterAddPosition() throws {
        print("🟢 TEST: testPortfolioTotalValue_updatesAfterAddPosition")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        print("🟢 Before position: totalValue = \(portfolio.totalValue)")
        XCTAssertEqual(portfolio.totalValue, 0, "Initial totalValue should be 0")
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        print("🟢 After add (before save): totalValue = \(portfolio.totalValue)")
        XCTAssertEqual(portfolio.totalValue, 20000, "totalValue should be 20000 (100 * 200)")
        
        try viewContext.save()
        
        print("🟢 After save: totalValue = \(portfolio.totalValue)")
        XCTAssertEqual(portfolio.totalValue, 20000, "totalValue should persist after save")
    }
    
    func testPortfolioTotalCost_updatesAfterAddPosition() throws {
        print("🟢 TEST: testPortfolioTotalCost_updatesAfterAddPosition")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        print("🟢 Before position: totalCost = \(portfolio.totalCost)")
        XCTAssertEqual(portfolio.totalCost, 0, "Initial totalCost should be 0")
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.portfolio = portfolio
        
        print("🟢 After add: totalCost = \(portfolio.totalCost)")
        XCTAssertEqual(portfolio.totalCost, 15000, "totalCost should be 15000 (100 * 150)")
        
        try viewContext.save()
        
        print("🟢 After save: totalCost = \(portfolio.totalCost)")
        XCTAssertEqual(portfolio.totalCost, 15000, "totalCost should persist after save")
    }
    
    func testPortfolioProfitLoss_updatesAfterAddPosition() throws {
        print("🟢 TEST: testPortfolioProfitLoss_updatesAfterAddPosition")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        // totalValue = 20000, totalCost = 15000, profitLoss = 5000
        print("🟢 totalValue = \(portfolio.totalValue), totalCost = \(portfolio.totalCost)")
        print("🟢 profitLoss = \(portfolio.totalProfitLoss)")
        
        XCTAssertEqual(portfolio.totalProfitLoss, 5000, "profitLoss should be 5000")
        XCTAssertEqual(portfolio.profitLossPercentage, 5000.0 / 15000.0, accuracy: 0.001, "profitLossPercentage should be ~33.3%")
        
        try viewContext.save()
    }
    
    func testPortfolioPercentage_updatesAfterAddPosition() throws {
        print("🟢 TEST: testPortfolioPercentage_updatesAfterAddPosition")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 100.0
        position.currentPrice = 150.0  // 50% gain
        position.portfolio = portfolio
        
        // profitLoss = 15000 - 10000 = 5000
        // profitLossPercentage = 5000 / 10000 = 0.5 = 50%
        
        print("🟢 profitLossPercentage = \(portfolio.profitLossPercentage)")
        XCTAssertEqual(portfolio.profitLossPercentage, 0.5, accuracy: 0.001, "profitLossPercentage should be 50%")
        
        try viewContext.save()
    }
    
    // MARK: - Portfolio Values After Edit Tests
    
    func testPortfolioValues_updateAfterEditPosition() throws {
        print("🟢 TEST: testPortfolioValues_updateAfterEditPosition")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        print("🟢 Initial: totalValue = \(portfolio.totalValue)")
        XCTAssertEqual(portfolio.totalValue, 20000)
        
        // Edit position: double the shares
        position.shares = 200
        
        print("🟢 After edit (before save): totalValue = \(portfolio.totalValue)")
        XCTAssertEqual(portfolio.totalValue, 40000, "totalValue should update to 40000")
        
        // Edit position: change price
        position.currentPrice = 250.0
        
        print("🟢 After price change: totalValue = \(portfolio.totalValue)")
        XCTAssertEqual(portfolio.totalValue, 50000, "totalValue should be 50000 (200 * 250)")
        
        try viewContext.save()
    }
    
    func testPortfolioValues_updateAfterDeletePosition() throws {
        print("🟢 TEST: testPortfolioValues_updateAfterDeletePosition")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position1 = Position(context: viewContext)
        position1.id = UUID()
        position1.symbol = "AAPL"
        position1.shares = 100
        position1.costBasis = 150.0
        position1.currentPrice = 200.0
        position1.portfolio = portfolio
        
        let position2 = Position(context: viewContext)
        position2.id = UUID()
        position2.symbol = "MSFT"
        position2.shares = 50
        position2.costBasis = 300.0
        position2.currentPrice = 400.0
        position2.portfolio = portfolio
        
        try viewContext.save()
        
        // AAPL: 100 * 200 = 20000
        // MSFT: 50 * 400 = 20000
        // Total: 40000
        print("🟢 Initial: totalValue = \(portfolio.totalValue)")
        XCTAssertEqual(portfolio.totalValue, 40000)
        
        // Delete AAPL
        viewContext.delete(position1)
        try viewContext.save()
        
        print("🟢 After delete AAPL: totalValue = \(portfolio.totalValue)")
        XCTAssertEqual(portfolio.totalValue, 20000, "totalValue should be 20000 after deleting AAPL")
    }
    
    // MARK: - Position Weight Tests
    
    func testPositionWeight_updatesAfterPortfolioChange() throws {
        print("🟢 TEST: testPositionWeight_updatesAfterPortfolioChange")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position1 = Position(context: viewContext)
        position1.id = UUID()
        position1.symbol = "AAPL"
        position1.shares = 100
        position1.costBasis = 150.0
        position1.currentPrice = 200.0
        position1.portfolio = portfolio
        
        // AAPL = 20000, total = 20000, weight = 100%
        print("🟢 AAPL weight (only position): \(position1.weightInPortfolio ?? -1)")
        XCTAssertEqual(position1.weightInPortfolio!, 1.0, accuracy: 0.001, "AAPL should be 100% of portfolio")
        
        let position2 = Position(context: viewContext)
        position2.id = UUID()
        position2.symbol = "MSFT"
        position2.shares = 50
        position2.costBasis = 300.0
        position2.currentPrice = 400.0
        position2.portfolio = portfolio
        
        // AAPL = 20000, MSFT = 20000, total = 40000
        // AAPL weight = 50%, MSFT weight = 50%
        print("🟢 AAPL weight (with MSFT): \(position1.weightInPortfolio ?? -1)")
        print("🟢 MSFT weight: \(position2.weightInPortfolio ?? -1)")
        
        XCTAssertEqual(position1.weightInPortfolio!, 0.5, accuracy: 0.001, "AAPL should be 50% of portfolio")
        XCTAssertEqual(position2.weightInPortfolio!, 0.5, accuracy: 0.001, "MSFT should be 50% of portfolio")
        
        try viewContext.save()
    }
    
    // MARK: - Multiple Positions Accuracy Tests
    
    func testMultiplePositions_allValuesCorrect() throws {
        print("🟢 TEST: testMultiplePositions_allValuesCorrect")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        // Create 5 positions with known values
        let positions: [(symbol: String, shares: Double, cost: Double, price: Double)] = [
            ("AAPL", 100, 150.0, 200.0),   // value: 20000, cost: 15000
            ("MSFT", 50, 300.0, 350.0),    // value: 17500, cost: 15000
            ("GOOGL", 20, 2500.0, 2800.0), // value: 56000, cost: 50000
            ("AMZN", 30, 3000.0, 3200.0),  // value: 96000, cost: 90000
            ("TSLA", 40, 800.0, 900.0)     // value: 36000, cost: 32000
        ]
        
        for pos in positions {
            let position = Position(context: viewContext)
            position.id = UUID()
            position.symbol = pos.symbol
            position.shares = pos.shares
            position.costBasis = pos.cost
            position.currentPrice = pos.price
            position.portfolio = portfolio
        }
        
        // Expected values:
        // totalValue = 20000 + 17500 + 56000 + 96000 + 36000 = 225500
        // totalCost = 15000 + 15000 + 50000 + 90000 + 32000 = 202000
        // profitLoss = 225500 - 202000 = 23500
        
        let expectedTotalValue = 225500.0
        let expectedTotalCost = 202000.0
        let expectedProfitLoss = 23500.0
        
        print("🟢 totalValue = \(portfolio.totalValue) (expected: \(expectedTotalValue))")
        print("🟢 totalCost = \(portfolio.totalCost) (expected: \(expectedTotalCost))")
        print("🟢 profitLoss = \(portfolio.totalProfitLoss) (expected: \(expectedProfitLoss))")
        
        XCTAssertEqual(portfolio.totalValue, expectedTotalValue, accuracy: 0.01, "totalValue should match expected")
        XCTAssertEqual(portfolio.totalCost, expectedTotalCost, accuracy: 0.01, "totalCost should match expected")
        XCTAssertEqual(portfolio.totalProfitLoss, expectedProfitLoss, accuracy: 0.01, "profitLoss should match expected")
        
        try viewContext.save()
    }
    
    // MARK: - Cash Position Tests
    
    func testCashPosition_currentValueEqualsTotalCost() throws {
        print("🟢 TEST: testCashPosition_currentValueEqualsTotalCost")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let cashPosition = Position(context: viewContext)
        cashPosition.id = UUID()
        cashPosition.symbol = ""
        cashPosition.name = "Cash"
        cashPosition.assetTypeRaw = AssetType.cash.rawValue
        cashPosition.shares = 10000
        cashPosition.costBasis = 1.0
        cashPosition.portfolio = portfolio
        
        // Cash position: currentValue should equal totalCost
        print("🟢 Cash currentValue = \(cashPosition.currentValue ?? -1)")
        print("🟢 Cash totalCost = \(cashPosition.totalCost)")
        
        XCTAssertEqual(cashPosition.currentValue, cashPosition.totalCost, "Cash currentValue should equal totalCost")
        XCTAssertEqual(portfolio.totalValue, 10000, "Portfolio totalValue should be 10000")
        
        try viewContext.save()
    }
}
