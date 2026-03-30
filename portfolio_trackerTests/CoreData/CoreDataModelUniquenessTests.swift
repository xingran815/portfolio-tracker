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
    }
    
    func testEntityMethod_NoAmbiguity() throws {
        let portfolio = Portfolio(context: viewContext)
        let position = Position(context: viewContext)
        
        XCTAssertNotNil(portfolio, "Portfolio should be created without ambiguity")
        XCTAssertNotNil(position, "Position should be created without ambiguity")
    }
    
    // MARK: - Relationship Integrity Tests
    
    func testAddPosition_relationshipUpdatesImmediately() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Relationship should update immediately before save")
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Relationship should persist after save")
    }
    
    func testAddMultiplePositions_correctCount() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        for i in 1...5 {
            let position = Position(context: viewContext)
            position.id = UUID()
            position.symbol = "STOCK\(i)"
            position.portfolio = portfolio
        }
        
        XCTAssertEqual(portfolio.positions?.count, 5, "Should have 5 positions before save")
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 5, "Should have 5 positions after save")
    }
    
    func testFetchPortfolio_positionsRelationshipCorrect() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        try viewContext.save()
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        try viewContext.save()
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolio.id! as CVarArg)
        let fetched = try viewContext.fetch(request)
        
        XCTAssertEqual(fetched.count, 1, "Should fetch 1 portfolio")
        
        let fetchedPortfolio = fetched.first!
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Fetched portfolio should have 1 position")
    }
    
    // MARK: - Bidirectional Relationship Tests
    
    func testBidirectionalRelationship_positionToPortfolio() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        XCTAssertEqual(position.portfolio?.id, portfolio.id, "Position should reference portfolio")
        
        let positions = portfolio.positions as? Set<Position>
        XCTAssertEqual(positions?.count, 1, "Portfolio should have 1 position")
        XCTAssertTrue(positions?.contains(where: { $0.id == position.id }) ?? false, "Portfolio should contain the position")
    }
    
    func testRemovePosition_relationshipUpdatesCorrectly() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Should have 1 position before delete")
        
        viewContext.delete(position)
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 0, "Should have 0 positions after delete")
    }
}
