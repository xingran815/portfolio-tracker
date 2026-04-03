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
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        XCTAssertEqual(portfolio.totalValue, 0, "Initial totalValue should be 0")
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        XCTAssertEqual(portfolio.totalValue, 20000, "totalValue should be 20000 (100 * 200)")
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.totalValue, 20000, "totalValue should persist after save")
    }
    
    func testPortfolioTotalCost_updatesAfterAddPosition() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        XCTAssertEqual(portfolio.totalCost, 0, "Initial totalCost should be 0")
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.portfolio = portfolio
        
        XCTAssertEqual(portfolio.totalCost, 15000, "totalCost should be 15000 (100 * 150)")
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.totalCost, 15000, "totalCost should persist after save")
    }
    
    func testPortfolioProfitLoss_updatesAfterAddPosition() throws {
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
        
        XCTAssertEqual(portfolio.totalProfitLoss, 5000, "profitLoss should be 5000")
        XCTAssertEqual(portfolio.profitLossPercentage, 5000.0 / 15000.0, accuracy: 0.001, "profitLossPercentage should be ~33.3%")
        
        try viewContext.save()
    }
    
    func testPortfolioPercentage_updatesAfterAddPosition() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 100.0
        position.currentPrice = 150.0
        position.portfolio = portfolio
        
        XCTAssertEqual(portfolio.profitLossPercentage, 0.5, accuracy: 0.001, "profitLossPercentage should be 50%")
        
        try viewContext.save()
    }
    
    // MARK: - Portfolio Values After Edit Tests
    
    func testPortfolioValues_updateAfterEditPosition() throws {
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
        
        XCTAssertEqual(portfolio.totalValue, 20000)
        
        position.shares = 200
        
        XCTAssertEqual(portfolio.totalValue, 40000, "totalValue should update to 40000")
        
        position.currentPrice = 250.0
        
        XCTAssertEqual(portfolio.totalValue, 50000, "totalValue should be 50000 (200 * 250)")
        
        try viewContext.save()
    }
    
    func testPortfolioValues_updateAfterDeletePosition() throws {
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
        
        XCTAssertEqual(portfolio.totalValue, 40000)
        
        viewContext.delete(position1)
        try viewContext.save()
        
        XCTAssertEqual(portfolio.totalValue, 20000, "totalValue should be 20000 after deleting AAPL")
    }
    
    // MARK: - Position Weight Tests
    
    func testPositionWeight_updatesAfterPortfolioChange() throws {
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
        
        XCTAssertEqual(position1.weightInPortfolio!, 1.0, accuracy: 0.001, "AAPL should be 100% of portfolio")
        
        let position2 = Position(context: viewContext)
        position2.id = UUID()
        position2.symbol = "MSFT"
        position2.shares = 50
        position2.costBasis = 300.0
        position2.currentPrice = 400.0
        position2.portfolio = portfolio
        
        XCTAssertEqual(position1.weightInPortfolio!, 0.5, accuracy: 0.001, "AAPL should be 50% of portfolio")
        XCTAssertEqual(position2.weightInPortfolio!, 0.5, accuracy: 0.001, "MSFT should be 50% of portfolio")
        
        try viewContext.save()
    }
    
    // MARK: - Multiple Positions Accuracy Tests
    
    func testMultiplePositions_allValuesCorrect() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        struct TestPositionData {
            let symbol: String
            let shares: Double
            let cost: Double
            let price: Double
        }
        
        let positions: [TestPositionData] = [
            TestPositionData(symbol: "AAPL", shares: 100, cost: 150.0, price: 200.0),
            TestPositionData(symbol: "MSFT", shares: 50, cost: 300.0, price: 350.0),
            TestPositionData(symbol: "GOOGL", shares: 20, cost: 2500.0, price: 2800.0),
            TestPositionData(symbol: "AMZN", shares: 30, cost: 3000.0, price: 3200.0),
            TestPositionData(symbol: "TSLA", shares: 40, cost: 800.0, price: 900.0)
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
        
        let expectedTotalValue = 225500.0
        let expectedTotalCost = 202000.0
        let expectedProfitLoss = 23500.0
        
        XCTAssertEqual(portfolio.totalValue, expectedTotalValue, accuracy: 0.01, "totalValue should match expected")
        XCTAssertEqual(portfolio.totalCost, expectedTotalCost, accuracy: 0.01, "totalCost should match expected")
        XCTAssertEqual(portfolio.totalProfitLoss, expectedProfitLoss, accuracy: 0.01, "profitLoss should match expected")
        
        try viewContext.save()
    }
    
    // MARK: - Cash Position Tests
    
    func testCashPosition_currentValueEqualsTotalCost() throws {
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
        
        XCTAssertEqual(cashPosition.currentValue, cashPosition.totalCost, "Cash currentValue should equal totalCost")
        XCTAssertEqual(portfolio.totalValue, 10000, "Portfolio totalValue should be 10000")
        
        try viewContext.save()
    }
}
