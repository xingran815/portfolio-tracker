//
//  ViewModelSyncTests.swift
//  portfolio_trackerTests
//
//  Tests for ViewModel data synchronization
//

import XCTest
import CoreData
@testable import portfolio_tracker

@MainActor
final class ViewModelSyncTests: XCTestCase {
    
    var container: NSPersistentContainer!
    var viewContext: NSManagedObjectContext!
    
    override func setUp() async throws {
        try await super.setUp()
        
        container = NSPersistentContainer(name: "portfolio_tracker")
        let description = container.persistentStoreDescriptions.first!
        description.type = NSInMemoryStoreType
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load store: \(error)")
            }
        }
        viewContext = container.viewContext
    }
    
    override func tearDown() async throws {
        container = nil
        viewContext = nil
        try await super.tearDown()
    }
    
    // MARK: - PortfolioListViewModel Tests
    
    func testPortfolioListViewModel_createPortfolio() throws {
        print("🟣 TEST: testPortfolioListViewModel_createPortfolio")
        
        let viewModel = PortfolioListViewModel(context: viewContext)
        
        viewModel.createPortfolio(name: "New Portfolio")
        
        // Verify portfolio was created in CoreData
        let request = Portfolio.fetchRequest()
        let portfolios = try viewContext.fetch(request)
        
        print("🟣 After create: CoreData has \(portfolios.count) portfolios")
        XCTAssertEqual(portfolios.count, 1, "Should have 1 portfolio")
        XCTAssertEqual(portfolios.first?.name, "New Portfolio")
    }
    
    func testPortfolioListViewModel_deletePortfolio() throws {
        print("🟣 TEST: testPortfolioListViewModel_deletePortfolio")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let viewModel = PortfolioListViewModel(context: viewContext)
        
        // Verify portfolio exists
        var request = Portfolio.fetchRequest()
        var portfolios = try viewContext.fetch(request)
        print("🟣 Before delete: CoreData has \(portfolios.count) portfolios")
        XCTAssertEqual(portfolios.count, 1)
        
        viewModel.deletePortfolio(portfolio)
        
        // Verify portfolio was deleted from CoreData
        request = Portfolio.fetchRequest()
        portfolios = try viewContext.fetch(request)
        print("🟣 After delete: CoreData has \(portfolios.count) portfolios")
        XCTAssertEqual(portfolios.count, 0, "Should have 0 portfolios after delete")
    }
    
    // MARK: - PortfolioDetailViewModel Tests
    
    func testPortfolioDetailViewModel_loadPositions() throws {
        print("🟣 TEST: testPortfolioDetailViewModel_loadPositions")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position1 = Position(context: viewContext)
        position1.id = UUID()
        position1.symbol = "AAPL"
        position1.shares = 100
        position1.portfolio = portfolio
        
        let position2 = Position(context: viewContext)
        position2.id = UUID()
        position2.symbol = "MSFT"
        position2.shares = 50
        position2.portfolio = portfolio
        
        try viewContext.save()
        
        let viewModel = PortfolioDetailViewModel(context: viewContext)
        viewModel.setPortfolio(portfolio)
        
        print("🟣 ViewModel loaded \(viewModel.positions.count) positions")
        XCTAssertEqual(viewModel.positions.count, 2, "Should load 2 positions")
    }
    
    func testPortfolioDetailViewModel_addPosition() throws {
        print("🟣 TEST: testPortfolioDetailViewModel_addPosition")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let viewModel = PortfolioDetailViewModel(context: viewContext)
        viewModel.setPortfolio(portfolio)
        
        print("🟣 Before add: viewModel.positions.count = \(viewModel.positions.count)")
        XCTAssertEqual(viewModel.positions.count, 0)
        
        try viewModel.addPositionWithTransaction(
            symbol: "AAPL",
            name: "Apple Inc.",
            assetType: .stock,
            market: .us,
            shares: 100,
            costBasis: 150
        )
        
        print("🟣 After add: viewModel.positions.count = \(viewModel.positions.count)")
        XCTAssertEqual(viewModel.positions.count, 1, "Should have 1 position after add")
    }
    
    func testPortfolioDetailViewModel_deletePosition() throws {
        print("🟣 TEST: testPortfolioDetailViewModel_deletePosition")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.portfolio = portfolio
        
        try viewContext.save()
        
        let viewModel = PortfolioDetailViewModel(context: viewContext)
        viewModel.setPortfolio(portfolio)
        
        print("🟣 Before delete: viewModel.positions.count = \(viewModel.positions.count)")
        XCTAssertEqual(viewModel.positions.count, 1)
        
        viewModel.deletePosition(position)
        
        print("🟣 After delete: viewModel.positions.count = \(viewModel.positions.count)")
        XCTAssertEqual(viewModel.positions.count, 0, "Should have 0 positions after delete")
    }
    
    // MARK: - Cross-ViewModel Sync Tests
    
    func testCrossViewModel_addPosition_updatesPortfolioInCoreData() throws {
        print("🟣 TEST: testCrossViewModel_addPosition_updatesPortfolioInCoreData")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let detailViewModel = PortfolioDetailViewModel(context: viewContext)
        
        detailViewModel.setPortfolio(portfolio)
        
        print("🟣 Before add:")
        print("🟣   portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        print("🟣   detailViewModel.positions.count = \(detailViewModel.positions.count)")
        
        try detailViewModel.addPositionWithTransaction(
            symbol: "AAPL",
            name: "Apple Inc.",
            assetType: .stock,
            market: .us,
            shares: 100,
            costBasis: 150
        )
        
        // Refresh portfolio from CoreData
        viewContext.refresh(portfolio, mergeChanges: false)
        
        print("🟣 After add:")
        print("🟣   portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        print("🟣   detailViewModel.positions.count = \(detailViewModel.positions.count)")
        
        XCTAssertEqual(detailViewModel.positions.count, 1, "DetailViewModel should have 1 position")
        XCTAssertEqual(portfolio.positions?.count, 1, "Portfolio should have 1 position in CoreData")
    }
}
