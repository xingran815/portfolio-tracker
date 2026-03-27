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
    
    func testPortfolioListViewModel_loadPortfolios() throws {
        print("🟣 TEST: testPortfolioListViewModel_loadPortfolios")
        
        let portfolio1 = Portfolio(context: viewContext)
        portfolio1.id = UUID()
        portfolio1.name = "Portfolio 1"
        
        let portfolio2 = Portfolio(context: viewContext)
        portfolio2.id = UUID()
        portfolio2.name = "Portfolio 2"
        
        try viewContext.save()
        
        let viewModel = PortfolioListViewModel(context: viewContext)
        
        print("🟣 ViewModel loaded \(viewModel.portfolios.count) portfolios")
        XCTAssertEqual(viewModel.portfolios.count, 2, "Should load 2 portfolios")
    }
    
    func testPortfolioListViewModel_createPortfolio() throws {
        print("🟣 TEST: testPortfolioListViewModel_createPortfolio")
        
        let viewModel = PortfolioListViewModel(context: viewContext)
        
        viewModel.createPortfolio(name: "New Portfolio")
        
        print("🟣 After create: viewModel.portfolios.count = \(viewModel.portfolios.count)")
        XCTAssertEqual(viewModel.portfolios.count, 1, "Should have 1 portfolio")
        XCTAssertEqual(viewModel.portfolios.first?.name, "New Portfolio")
    }
    
    func testPortfolioListViewModel_deletePortfolio() throws {
        print("🟣 TEST: testPortfolioListViewModel_deletePortfolio")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let viewModel = PortfolioListViewModel(context: viewContext)
        
        print("🟣 Before delete: viewModel.portfolios.count = \(viewModel.portfolios.count)")
        XCTAssertEqual(viewModel.portfolios.count, 1)
        
        viewModel.deletePortfolio(portfolio)
        
        print("🟣 After delete: viewModel.portfolios.count = \(viewModel.portfolios.count)")
        XCTAssertEqual(viewModel.portfolios.count, 0, "Should have 0 portfolios after delete")
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
    
    func testCrossViewModel_addPosition_updatesPortfolioInBothViewModels() throws {
        print("🟣 TEST: testCrossViewModel_addPosition_updatesPortfolioInBothViewModels")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let listViewModel = PortfolioListViewModel(context: viewContext)
        let detailViewModel = PortfolioDetailViewModel(context: viewContext)
        
        detailViewModel.setPortfolio(portfolio)
        
        print("🟣 Before add:")
        print("🟣   listViewModel portfolio.positions.count = \(listViewModel.portfolios.first?.positions?.count ?? -1)")
        print("🟣   detailViewModel.positions.count = \(detailViewModel.positions.count)")
        
        try detailViewModel.addPositionWithTransaction(
            symbol: "AAPL",
            name: "Apple Inc.",
            assetType: .stock,
            market: .us,
            shares: 100,
            costBasis: 150
        )
        
        listViewModel.loadPortfolios()
        
        print("🟣 After add:")
        print("🟣   listViewModel portfolio.positions.count = \(listViewModel.portfolios.first?.positions?.count ?? -1)")
        print("🟣   detailViewModel.positions.count = \(detailViewModel.positions.count)")
        
        XCTAssertEqual(detailViewModel.positions.count, 1, "DetailViewModel should have 1 position")
        XCTAssertEqual(listViewModel.portfolios.first?.positions?.count, 1, "ListViewModel's portfolio should have 1 position")
    }
}
