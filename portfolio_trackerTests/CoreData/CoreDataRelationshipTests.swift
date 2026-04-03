//
//  CoreDataRelationshipTests.swift
//  portfolio_trackerTests
//
//  Tests for CoreData relationship consistency
//

import XCTest
import CoreData
@testable import portfolio_tracker

@MainActor
final class CoreDataRelationshipTests: XCTestCase {
    
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
    
    // MARK: - Portfolio-Position Relationship Tests
    
    func testAddPosition_updatesPortfolioPositions() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        let positions = portfolio.positions as? Set<Position>
        XCTAssertNotNil(positions, "positions should not be nil")
        XCTAssertEqual(positions?.count, 1, "positions count should be 1")
        XCTAssertTrue(positions?.contains(position) ?? false, "positions should contain the new position")
    }
    
    func testDeletePosition_updatesPortfolioPositions() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "should have 1 position before delete")
        
        viewContext.delete(position)
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 0, "should have 0 positions after delete")
    }
    
    func testFetchPortfolio_afterAddingPosition() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        let request = Portfolio.fetchRequest()
        guard let portfolioId = portfolio.id else {
            XCTFail("Portfolio ID should not be nil")
            return
        }
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        
        let fetchedPortfolios = try viewContext.fetch(request)
        XCTAssertEqual(fetchedPortfolios.count, 1, "should fetch 1 portfolio")
        
        guard let fetchedPortfolio = fetchedPortfolios.first else {
            XCTFail("Should have fetched a portfolio")
            return
        }
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "fetched portfolio should have 1 position")
    }
    
    func testMultiplePositions_correctCount() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        for index in 1...5 {
            let position = Position(context: viewContext)
            position.id = UUID()
            position.symbol = "STOCK\(index)"
            position.portfolio = portfolio
        }
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 5, "should have 5 positions")
    }
    
    func testPositionPortfolioRelationship_bidirectional() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        XCTAssertEqual(position.portfolio?.id, portfolio.id, "position.portfolio should match")
        XCTAssertEqual(portfolio.positions?.count, 1, "portfolio.positions should contain 1 position")
    }
}
