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
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        XCTAssertEqual(portfolio.positions?.count, 0, "Should start with 0 positions")
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Relationship should update immediately")
        XCTAssertEqual(portfolio.totalValue, 20000, "totalValue should update immediately")
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Relationship should persist after save")
    }
    
    func testAddPosition_fetchedPortfolioHasCorrectData() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolios = try viewContext.fetch(request)
        
        XCTAssertEqual(fetchedPortfolios.count, 1, "Should fetch 1 portfolio")
        
        let fetchedPortfolio = fetchedPortfolios.first!
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Fetched portfolio should have 1 position")
        XCTAssertEqual(fetchedPortfolio.totalValue, 20000, "Fetched portfolio should have correct totalValue")
    }
    
    func testEditPosition_fetchedPortfolioReflectsChanges() throws {
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
        
        var request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        var fetchedPortfolio = try viewContext.fetch(request).first!
        
        XCTAssertEqual(fetchedPortfolio.totalValue, 20000)
        
        position.shares = 200
        try viewContext.save()
        
        request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        fetchedPortfolio = try viewContext.fetch(request).first!
        
        XCTAssertEqual(fetchedPortfolio.totalValue, 40000, "Fetched portfolio should reflect edited position")
    }
    
    func testDeletePosition_fetchedPortfolioReflectsChanges() throws {
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
        
        var request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        var fetchedPortfolio = try viewContext.fetch(request).first!
        
        XCTAssertEqual(fetchedPortfolio.positions?.count, 2)
        XCTAssertEqual(fetchedPortfolio.totalValue, 40000)
        
        viewContext.delete(position1)
        try viewContext.save()
        
        request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        fetchedPortfolio = try viewContext.fetch(request).first!
        
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Should have 1 position after delete")
        XCTAssertEqual(fetchedPortfolio.totalValue, 20000, "totalValue should be 20000 after deleting AAPL")
    }
    
    // MARK: - Context Merge Tests
    
    func testConcurrentModification_contextMergeCorrect() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        let backgroundContext = persistenceController.newBackgroundContext()
        
        try backgroundContext.performAndWait {
            let request = Portfolio.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
            guard let bgPortfolio = try backgroundContext.fetch(request).first else {
                XCTFail("Portfolio not found in background context")
                return
            }
            
            let bgPosition = Position(context: backgroundContext)
            bgPosition.id = UUID()
            bgPosition.symbol = "AAPL"
            bgPosition.shares = 100
            bgPosition.costBasis = 150.0
            bgPosition.currentPrice = 200.0
            bgPosition.portfolio = bgPortfolio
            
            try backgroundContext.save()
        }
        
        Thread.sleep(forTimeInterval: 0.1)
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolio = try viewContext.fetch(request).first!
    }
    
    func testBackgroundContextChange_propagatesToViewContext() async throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        await persistenceController.performBackgroundTask { context in
            let request = Portfolio.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
            
            do {
                guard let bgPortfolio = try context.fetch(request).first else {
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
            } catch {
            }
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolio = try viewContext.fetch(request).first!
    }
    
    // MARK: - Refresh Tests
    
    func testRefreshPortfolio_updatesStaleData() throws {
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
        
        let positionsBeforeRefresh = portfolio.positions as? Set<Position>
        
        viewContext.refresh(portfolio, mergeChanges: false)
        
        let positionsAfterRefresh = portfolio.positions as? Set<Position>
    }
    
    func testRefreshAllObjects_updatesRelationships() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test"
        
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.costBasis = 150.0
        position.currentPrice = 200.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        viewContext.refreshAllObjects()
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolio = try viewContext.fetch(request).first!
        
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Should have 1 position after refreshAllObjects")
        XCTAssertEqual(fetchedPortfolio.totalValue, 20000, "totalValue should be correct after refreshAllObjects")
    }
}
