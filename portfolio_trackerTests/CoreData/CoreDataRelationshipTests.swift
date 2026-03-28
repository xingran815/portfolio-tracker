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
        print("🔵 TEST: testAddPosition_updatesPortfolioPositions")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        print("🔵 Before add: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        print("🔵 After save: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        
        let positions = portfolio.positions as? Set<Position>
        XCTAssertNotNil(positions, "positions should not be nil")
        XCTAssertEqual(positions?.count, 1, "positions count should be 1")
        XCTAssertTrue(positions?.contains(position) ?? false, "positions should contain the new position")
    }
    
    func testDeletePosition_updatesPortfolioPositions() throws {
        print("🔵 TEST: testDeletePosition_updatesPortfolioPositions")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        print("🔵 Before delete: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        XCTAssertEqual(portfolio.positions?.count, 1, "should have 1 position before delete")
        
        viewContext.delete(position)
        try viewContext.save()
        
        print("🔵 After delete: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        XCTAssertEqual(portfolio.positions?.count, 0, "should have 0 positions after delete")
    }
    
    func testFetchPortfolio_afterAddingPosition() throws {
        print("🔵 TEST: testFetchPortfolio_afterAddingPosition")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        print("🔵 After first save: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        print("🔵 After second save: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolio.id! as CVarArg)
        
        let fetchedPortfolios = try viewContext.fetch(request)
        XCTAssertEqual(fetchedPortfolios.count, 1, "should fetch 1 portfolio")
        
        let fetchedPortfolio = fetchedPortfolios.first!
        print("🔵 Fetched portfolio: positions.count = \(fetchedPortfolio.positions?.count ?? -1)")
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "fetched portfolio should have 1 position")
    }
    
    func testMultiplePositions_correctCount() throws {
        print("🔵 TEST: testMultiplePositions_correctCount")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        for i in 1...5 {
            let position = Position(context: viewContext)
            position.id = UUID()
            position.symbol = "STOCK\(i)"
            position.portfolio = portfolio
        }
        
        try viewContext.save()
        
        print("🔵 After adding 5 positions: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        XCTAssertEqual(portfolio.positions?.count, 5, "should have 5 positions")
    }
    
    func testPositionPortfolioRelationship_bidirectional() throws {
        print("🔵 TEST: testPositionPortfolioRelationship_bidirectional")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        print("🔵 position.portfolio.name = \(position.portfolio?.name ?? "nil")")
        print("🔵 portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        
        XCTAssertEqual(position.portfolio?.id, portfolio.id, "position.portfolio should match")
        XCTAssertEqual(portfolio.positions?.count, 1, "portfolio.positions should contain 1 position")
    }
}
