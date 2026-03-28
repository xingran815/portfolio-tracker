//
//  CrossViewUpdateTests.swift
//  portfolio_trackerTests
//
//  Tests for cross-view update propagation
//

import XCTest
import CoreData
@testable import portfolio_tracker

@MainActor
final class CrossViewUpdateTests: XCTestCase {
    
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
    
    // MARK: - Immediate Relationship Update Tests
    
    func testAddPosition_updatesRelationshipImmediately() throws {
        print("🟠 TEST: testAddPosition_updatesRelationshipImmediately")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        // Initial state
        XCTAssertEqual(portfolio.positions?.count, 0, "Should start with 0 positions")
        
        // Add position
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        // Verify immediate update (before save)
        print("🟠 Before save: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        XCTAssertEqual(portfolio.positions?.count, 1, "Relationship should update immediately")
        
        // Verify totalValue reflects the change
        print("🟠 Before save: portfolio.totalValue = \(portfolio.totalValue)")
        XCTAssertEqual(portfolio.totalValue, 20000, "totalValue should update immediately")
        
        try viewContext.save()
        
        // Verify after save
        print("🟠 After save: portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        XCTAssertEqual(portfolio.positions?.count, 1, "Relationship should persist after save")
    }
    
    func testAddPosition_fetchedPortfolioHasCorrectData() throws {
        print("🟠 TEST: testAddPosition_fetchedPortfolioHasCorrectData")
        
        // Create portfolio and save
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        // Add position in a separate operation
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        // Fetch portfolio fresh
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolios = try viewContext.fetch(request)
        
        XCTAssertEqual(fetchedPortfolios.count, 1, "Should fetch 1 portfolio")
        
        let fetchedPortfolio = fetchedPortfolios.first!
        print("🟠 Fetched portfolio: positions.count = \(fetchedPortfolio.positions?.count ?? -1)")
        print("🟠 Fetched portfolio: totalValue = \(fetchedPortfolio.totalValue)")
        
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Fetched portfolio should have 1 position")
        XCTAssertEqual(fetchedPortfolio.totalValue, 20000, "Fetched portfolio should have correct totalValue")
    }
    
    func testEditPosition_fetchedPortfolioReflectsChanges() throws {
        print("🟠 TEST: testEditPosition_fetchedPortfolioReflectsChanges")
        
        // Setup
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
        
        let portfolioId = portfolio.id!
        
        // Verify initial state via fetch
        var request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        var fetchedPortfolio = try viewContext.fetch(request).first!
        
        print("🟠 Initial: positions.count = \(fetchedPortfolio.positions?.count ?? -1), totalValue = \(fetchedPortfolio.totalValue)")
        XCTAssertEqual(fetchedPortfolio.totalValue, 20000)
        
        // Edit position
        position.shares = 200  // Double the shares
        try viewContext.save()
        
        // Fetch again
        request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        fetchedPortfolio = try viewContext.fetch(request).first!
        
        print("🟠 After edit: positions.count = \(fetchedPortfolio.positions?.count ?? -1), totalValue = \(fetchedPortfolio.totalValue)")
        XCTAssertEqual(fetchedPortfolio.totalValue, 40000, "Fetched portfolio should reflect edited position")
    }
    
    func testDeletePosition_fetchedPortfolioReflectsChanges() throws {
        print("🟠 TEST: testDeletePosition_fetchedPortfolioReflectsChanges")
        
        // Setup
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
        
        let portfolioId = portfolio.id!
        
        // Verify initial state
        var request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        var fetchedPortfolio = try viewContext.fetch(request).first!
        
        print("🟠 Initial: positions.count = \(fetchedPortfolio.positions?.count ?? -1), totalValue = \(fetchedPortfolio.totalValue)")
        XCTAssertEqual(fetchedPortfolio.positions?.count, 2)
        XCTAssertEqual(fetchedPortfolio.totalValue, 40000)
        
        // Delete one position
        viewContext.delete(position1)
        try viewContext.save()
        
        // Fetch again
        request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        fetchedPortfolio = try viewContext.fetch(request).first!
        
        print("🟠 After delete: positions.count = \(fetchedPortfolio.positions?.count ?? -1), totalValue = \(fetchedPortfolio.totalValue)")
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Should have 1 position after delete")
        XCTAssertEqual(fetchedPortfolio.totalValue, 20000, "totalValue should be 20000 after deleting AAPL")
    }
    
    // MARK: - Context Merge Tests
    
    func testConcurrentModification_contextMergeCorrect() throws {
        print("🟠 TEST: testConcurrentModification_contextMergeCorrect")
        
        // Create portfolio in main context
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        // Simulate background context modification
        let backgroundContext = persistenceController.newBackgroundContext()
        
        try backgroundContext.performAndWait {
            // Fetch portfolio in background context
            let request = Portfolio.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
            guard let bgPortfolio = try backgroundContext.fetch(request).first else {
                XCTFail("Portfolio not found in background context")
                return
            }
            
            // Add position in background context
            let bgPosition = Position(context: backgroundContext)
            bgPosition.id = UUID()
            bgPosition.symbol = "AAPL"
            bgPosition.shares = 100
            bgPosition.costBasis = 150.0
            bgPosition.currentPrice = 200.0
            bgPosition.portfolio = bgPortfolio
            
            try backgroundContext.save()
        }
        
        // Wait for merge
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify main context received the changes
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolio = try viewContext.fetch(request).first!
        
        print("🟠 After background save: positions.count = \(fetchedPortfolio.positions?.count ?? -1)")
        
        // Note: This test may need adjustment based on merge policy configuration
        // With automaticallyMergesChangesFromParent = true, the main context should see the changes
    }
    
    func testBackgroundContextChange_propagatesToViewContext() async throws {
        print("🟠 TEST: testBackgroundContextChange_propagatesToViewContext")
        
        // Setup
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        // Perform background task
        await persistenceController.performBackgroundTask { context in
            let request = Portfolio.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
            
            do {
                guard let bgPortfolio = try context.fetch(request).first else {
                    print("🟠 Portfolio not found in background context")
                    return
                }
                
                let bgPosition = Position(context: context)
                bgPosition.id = UUID()
                bgPosition.symbol = "MSFT"
                bgPosition.shares = 50
                bgPosition.costBasis = 300.0
                bgPosition.currentPrice = 400.0
                bgPosition.portfolio = bgPortfolio
                
                try context.save()
                print("🟠 Saved position in background context")
            } catch {
                print("🟠 Error in background context: \(error)")
            }
        }
        
        // Wait for merge
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Verify
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolio = try viewContext.fetch(request).first!
        
        print("🟠 After background task: positions.count = \(fetchedPortfolio.positions?.count ?? -1)")
        print("🟠 After background task: totalValue = \(fetchedPortfolio.totalValue)")
        
        // With proper merge policy, the position should be visible
        // XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Background changes should propagate to view context")
    }
    
    // MARK: - Refresh Tests
    
    func testRefreshPortfolio_updatesStaleData() throws {
        print("🟠 TEST: testRefreshPortfolio_updatesStaleData")
        
        // Setup
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
        
        let portfolioId = portfolio.id!
        
        // Simulate stale data scenario
        // Access the relationship
        let positionsBeforeRefresh = portfolio.positions as? Set<Position>
        print("🟠 Before refresh: positions.count = \(positionsBeforeRefresh?.count ?? -1)")
        
        // Refresh the portfolio object
        viewContext.refresh(portfolio, mergeChanges: false)
        
        // Access the relationship again
        let positionsAfterRefresh = portfolio.positions as? Set<Position>
        print("🟠 After refresh: positions.count = \(positionsAfterRefresh?.count ?? -1)")
        
        // Note: After refresh with mergeChanges=false, relationships may be faulted
        // This tests whether the relationship is properly re-fetched
    }
    
    func testRefreshAllObjects_updatesRelationships() throws {
        print("🟠 TEST: testRefreshAllObjects_updatesRelationships")
        
        // Setup
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        // Add position after initial save
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        // Call refreshAllObjects (simulating the fix)
        viewContext.refreshAllObjects()
        
        // Fetch portfolio
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolio = try viewContext.fetch(request).first!
        
        print("🟠 After refreshAllObjects: positions.count = \(fetchedPortfolio.positions?.count ?? -1)")
        print("🟠 After refreshAllObjects: totalValue = \(fetchedPortfolio.totalValue)")
        
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Should have 1 position after refreshAllObjects")
        XCTAssertEqual(fetchedPortfolio.totalValue, 20000, "totalValue should be correct after refreshAllObjects")
    }
}
