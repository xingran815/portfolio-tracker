//
//  CoreDataModelUniquenessTests.swift
//  portfolio_trackerTests
//
//  Verifies that only one NSManagedObjectModel is loaded
//  and entity resolution works correctly
//

import XCTest
import CoreData
@testable import portfolio_tracker

@MainActor
final class CoreDataModelUniquenessTests: XCTestCase {
    
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
    
    // MARK: - Model Uniqueness Tests
    
    func testEntityDescription_UniqueMatch() throws {
        print("🔵 TEST: testEntityDescription_UniqueMatch")
        
        // This should NOT throw the error:
        // "Failed to find a unique match for an NSEntityDescription"
        
        let portfolioEntity = NSEntityDescription.entity(
            forEntityName: "Portfolio",
            in: viewContext
        )
        let positionEntity = NSEntityDescription.entity(
            forEntityName: "Position",
            in: viewContext
        )
        
        XCTAssertNotNil(portfolioEntity, "Portfolio entity should be found")
        XCTAssertNotNil(positionEntity, "Position entity should be found")
        
        print("🔵 Portfolio entity name: \(portfolioEntity?.name ?? "nil")")
        print("🔵 Position entity name: \(positionEntity?.name ?? "nil")")
    }
    
    func testEntityMethod_NoAmbiguity() throws {
        print("🔵 TEST: testEntityMethod_NoAmbiguity")
        
        // This would fail if multiple models exist
        // +[Portfolio entity] would throw ambiguity error
        
        let portfolio = Portfolio(context: viewContext)
        let position = Position(context: viewContext)
        
        XCTAssertNotNil(portfolio, "Portfolio should be created without ambiguity")
        XCTAssertNotNil(position, "Position should be created without ambiguity")
        
        print("🔵 Created Portfolio: \(portfolio)")
        print("🔵 Created Position: \(position)")
    }
    
    // MARK: - Relationship Integrity Tests
    
    func testAddPosition_relationshipUpdatesImmediately() throws {
        print("🔵 TEST: testAddPosition_relationshipUpdatesImmediately")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        // BEFORE save - relationship should work
        print("🔵 Before save: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        XCTAssertEqual(portfolio.positions?.count, 1, "Relationship should update immediately before save")
        
        try viewContext.save()
        
        // AFTER save - relationship should still work
        print("🔵 After save: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        XCTAssertEqual(portfolio.positions?.count, 1, "Relationship should persist after save")
    }
    
    func testAddMultiplePositions_correctCount() throws {
        print("🔵 TEST: testAddMultiplePositions_correctCount")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        for i in 1...5 {
            let position = Position(context: viewContext)
            position.id = UUID()
            position.symbol = "STOCK\(i)"
            position.portfolio = portfolio
        }
        
        print("🔵 Before save: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        XCTAssertEqual(portfolio.positions?.count, 5, "Should have 5 positions before save")
        
        try viewContext.save()
        
        print("🔵 After save: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        XCTAssertEqual(portfolio.positions?.count, 5, "Should have 5 positions after save")
    }
    
    func testFetchPortfolio_positionsRelationshipCorrect() throws {
        print("🔵 TEST: testFetchPortfolio_positionsRelationshipCorrect")
        
        // Create and save portfolio first
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        try viewContext.save()
        
        // Add position to existing portfolio
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        try viewContext.save()
        
        // Fetch portfolio fresh from context
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolio.id! as CVarArg)
        let fetched = try viewContext.fetch(request)
        
        XCTAssertEqual(fetched.count, 1, "Should fetch 1 portfolio")
        
        let fetchedPortfolio = fetched.first!
        print("🔵 Fetched portfolio: positions.count = \(fetchedPortfolio.positions?.count ?? -1)")
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Fetched portfolio should have 1 position")
    }
    
    // MARK: - Bidirectional Relationship Tests
    
    func testBidirectionalRelationship_positionToPortfolio() throws {
        print("🔵 TEST: testBidirectionalRelationship_positionToPortfolio")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        // Verify position -> portfolio
        XCTAssertEqual(position.portfolio?.id, portfolio.id, "Position should reference portfolio")
        
        // Verify portfolio -> positions
        let positions = portfolio.positions as? Set<Position>
        XCTAssertEqual(positions?.count, 1, "Portfolio should have 1 position")
        XCTAssertTrue(positions?.contains(where: { $0.id == position.id }) ?? false, "Portfolio should contain the position")
        
        print("🔵 Bidirectional relationship verified correctly")
    }
    
    func testRemovePosition_relationshipUpdatesCorrectly() throws {
        print("🔵 TEST: testRemovePosition_relationshipUpdatesCorrectly")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Should have 1 position before delete")
        
        // Delete position
        viewContext.delete(position)
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 0, "Should have 0 positions after delete")
        print("🔵 Relationship updated correctly after delete")
    }
}
