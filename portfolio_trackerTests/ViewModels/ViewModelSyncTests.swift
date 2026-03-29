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
    
    // MARK: - PortfolioListViewModel Tests
    
    func testPortfolioListViewModel_createPortfolio() throws {
        let viewModel = PortfolioListViewModel(context: viewContext)
        
        viewModel.createPortfolio(name: "New Portfolio")
        
        let request = Portfolio.fetchRequest()
        let portfolios = try viewContext.fetch(request)
        
        XCTAssertEqual(portfolios.count, 1, "Should have 1 portfolio")
        XCTAssertEqual(portfolios.first?.name, "New Portfolio")
    }
    
    func testPortfolioListViewModel_deletePortfolio() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let viewModel = PortfolioListViewModel(context: viewContext)
        
        var request = Portfolio.fetchRequest()
        var portfolios = try viewContext.fetch(request)
        XCTAssertEqual(portfolios.count, 1)
        
        viewModel.deletePortfolio(portfolio)
        
        request = Portfolio.fetchRequest()
        portfolios = try viewContext.fetch(request)
        XCTAssertEqual(portfolios.count, 0, "Should have 0 portfolios after delete")
    }
    
    // MARK: - PortfolioDetailViewModel Tests
    
    func testPortfolioDetailViewModel_loadPositions() throws {
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
        
        XCTAssertEqual(viewModel.positions.count, 2, "Should load 2 positions")
    }
    
    func testPortfolioDetailViewModel_addPosition() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let viewModel = PortfolioDetailViewModel(context: viewContext)
        viewModel.setPortfolio(portfolio)
        
        XCTAssertEqual(viewModel.positions.count, 0)
        
        try viewModel.addPositionWithTransaction(
            symbol: "AAPL",
            name: "Apple Inc.",
            assetType: .stock,
            market: .us,
            shares: 100,
            costBasis: 150
        )
        
        XCTAssertEqual(viewModel.positions.count, 1, "Should have 1 position after add")
    }
    
    func testPortfolioDetailViewModel_deletePosition() throws {
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
        
        XCTAssertEqual(viewModel.positions.count, 1)
        
        viewModel.deletePosition(position)
        
        XCTAssertEqual(viewModel.positions.count, 0, "Should have 0 positions after delete")
    }
    
    // MARK: - Cross-ViewModel Sync Tests
    
    func testCrossViewModel_addPosition_updatesPortfolioInCoreData() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let detailViewModel = PortfolioDetailViewModel(context: viewContext)
        
        detailViewModel.setPortfolio(portfolio)
        
        try detailViewModel.addPositionWithTransaction(
            symbol: "AAPL",
            name: "Apple Inc.",
            assetType: .stock,
            market: .us,
            shares: 100,
            costBasis: 150
        )
        
        viewContext.refresh(portfolio, mergeChanges: false)
        
        XCTAssertEqual(detailViewModel.positions.count, 1, "DetailViewModel should have 1 position")
        XCTAssertEqual(portfolio.positions?.count, 1, "Portfolio should have 1 position in CoreData")
    }
    
    // MARK: - Portfolio Total Value Update Tests
    
    func testAddPosition_updatesPortfolioTotalValue_sameInstance() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 0, "Initial: should have 0 positions")
        XCTAssertEqual(portfolio.totalValue, 0, "Initial: totalValue should be 0")
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "CASH"
        position.name = "现金"
        position.assetTypeRaw = AssetType.cash.rawValue
        position.shares = 10000
        position.costBasis = 1.0
        position.currentPrice = 1.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Same instance should have 1 position after save")
        XCTAssertEqual(portfolio.totalValue, 10000, "Same instance should have totalValue = 10000")
    }
    
    func testAddPosition_updatesPortfolioTotalValue_refreshedInstance() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "CASH"
        position.name = "现金"
        position.assetTypeRaw = AssetType.cash.rawValue
        position.shares = 10000
        position.costBasis = 1.0
        position.currentPrice = 1.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolio.id! as CVarArg)
        let fetchedPortfolios = try viewContext.fetch(request)
        let fetchedPortfolio = fetchedPortfolios.first!
        
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Fetched portfolio should have 1 position")
        XCTAssertEqual(fetchedPortfolio.totalValue, 10000, "Fetched portfolio should have totalValue = 10000")
    }
    
    func testDeletePosition_updatesPortfolioTotalValue() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "CASH"
        position.name = "现金"
        position.assetTypeRaw = AssetType.cash.rawValue
        position.shares = 10000
        position.costBasis = 1.0
        position.currentPrice = 1.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Should have 1 position before delete")
        XCTAssertEqual(portfolio.totalValue, 10000, "totalValue should be 10000 before delete")
        
        viewContext.delete(position)
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 0, "Should have 0 positions after delete")
        XCTAssertEqual(portfolio.totalValue, 0, "totalValue should be 0 after delete")
    }
    
    func testMultiplePositionChanges_updatesPortfolioCorrectly() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let pos1 = Position(context: viewContext)
        pos1.id = UUID()
        pos1.symbol = "CASH1"
        pos1.assetTypeRaw = AssetType.cash.rawValue
        pos1.shares = 5000
        pos1.costBasis = 1.0
        pos1.currentPrice = 1.0
        pos1.portfolio = portfolio
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.totalValue, 5000, "totalValue should be 5000")
        
        let pos2 = Position(context: viewContext)
        pos2.id = UUID()
        pos2.symbol = "CASH2"
        pos2.assetTypeRaw = AssetType.cash.rawValue
        pos2.shares = 3000
        pos2.costBasis = 1.0
        pos2.currentPrice = 1.0
        pos2.portfolio = portfolio
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 2, "Should have 2 positions")
        XCTAssertEqual(portfolio.totalValue, 8000, "totalValue should be 8000")
        
        viewContext.delete(pos1)
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Should have 1 position after delete")
        XCTAssertEqual(portfolio.totalValue, 3000, "totalValue should be 3000")
    }
    
    // MARK: - Simulating @FetchRequest behavior
    
    func testFetchRequest_simulation_portfolioFetchAfterPositionChange() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        var request = Portfolio.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        var fetchedPortfolios = try viewContext.fetch(request)
        
        XCTAssertEqual(fetchedPortfolios.count, 1)
        XCTAssertEqual(fetchedPortfolios.first?.positions?.count, 0)
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "CASH"
        position.assetTypeRaw = AssetType.cash.rawValue
        position.shares = 10000
        position.costBasis = 1.0
        position.currentPrice = 1.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        request = Portfolio.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        fetchedPortfolios = try viewContext.fetch(request)
        
        XCTAssertEqual(fetchedPortfolios.count, 1)
        XCTAssertEqual(fetchedPortfolios.first?.positions?.count, 1, "Re-fetched portfolio should have 1 position")
        XCTAssertEqual(fetchedPortfolios.first?.totalValue, 10000, "Re-fetched portfolio should have totalValue = 10000")
    }
    
    func testFetchRequest_simulation_withPortfolioUpdate() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        portfolio.updatedAt = Date()
        
        try viewContext.save()
        
        var request = Portfolio.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        var fetchedPortfolios = try viewContext.fetch(request)
        let originalUpdatedAt = fetchedPortfolios.first?.updatedAt
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "CASH"
        position.assetTypeRaw = AssetType.cash.rawValue
        position.shares = 10000
        position.costBasis = 1.0
        position.currentPrice = 1.0
        position.portfolio = portfolio
        
        portfolio.updatedAt = Date()
        
        try viewContext.save()
        
        request = Portfolio.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        fetchedPortfolios = try viewContext.fetch(request)
        let newUpdatedAt = fetchedPortfolios.first?.updatedAt
        
        XCTAssertNotEqual(originalUpdatedAt, newUpdatedAt, "updatedAt should have changed")
        XCTAssertEqual(fetchedPortfolios.first?.positions?.count, 1)
        XCTAssertEqual(fetchedPortfolios.first?.totalValue, 10000)
    }
    
    // MARK: - Cash Position Tests
    
    func testAddCashPosition_updatesPortfolioMetrics() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let initialPositionsCount = portfolio.positions?.count ?? -1
        let initialTotalValue = portfolio.totalValue
        
        XCTAssertEqual(initialPositionsCount, 0, "Should start with 0 positions")
        XCTAssertEqual(initialTotalValue, 0, "Should start with 0 totalValue")
        
        let cashPosition = Position(context: viewContext)
        cashPosition.id = UUID()
        cashPosition.symbol = ""
        cashPosition.name = "现金"
        cashPosition.assetTypeRaw = AssetType.cash.rawValue
        cashPosition.shares = 10000
        cashPosition.costBasis = 1.0
        cashPosition.currentPrice = 1.0
        cashPosition.portfolio = portfolio
        
        portfolio.updatedAt = Date()
        
        try viewContext.save()
        
        let afterPositionsCount = portfolio.positions?.count ?? -1
        let afterTotalValue = portfolio.totalValue
        let afterTotalCost = portfolio.totalCost
        let afterProfitLossPercentage = portfolio.profitLossPercentage
        
        XCTAssertEqual(afterPositionsCount, 1, "positions.count should be 1 after adding cash")
        XCTAssertEqual(afterTotalValue, 10000, "totalValue should be 10000 after adding cash")
        XCTAssertEqual(afterTotalCost, 10000, "totalCost should be 10000")
        XCTAssertEqual(afterProfitLossPercentage, 0, accuracy: 0.001, "profitLossPercentage should be 0 for cash")
    }
    
    func testDeleteCashPosition_updatesPortfolioMetrics() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let cashPosition = Position(context: viewContext)
        cashPosition.id = UUID()
        cashPosition.symbol = ""
        cashPosition.name = "现金"
        cashPosition.assetTypeRaw = AssetType.cash.rawValue
        cashPosition.shares = 10000
        cashPosition.costBasis = 1.0
        cashPosition.currentPrice = 1.0
        cashPosition.portfolio = portfolio
        
        let stockPosition = Position(context: viewContext)
        stockPosition.id = UUID()
        stockPosition.symbol = "AAPL"
        stockPosition.name = "Apple"
        stockPosition.assetTypeRaw = AssetType.stock.rawValue
        stockPosition.shares = 100
        stockPosition.costBasis = 150
        stockPosition.currentPrice = 200
        stockPosition.portfolio = portfolio
        
        try viewContext.save()
        
        let beforePositionsCount = portfolio.positions?.count ?? -1
        let beforeTotalValue = portfolio.totalValue
        let beforeTotalCost = portfolio.totalCost
        
        XCTAssertEqual(beforePositionsCount, 2)
        XCTAssertEqual(beforeTotalValue, 30000, accuracy: 0.001)
        XCTAssertEqual(beforeTotalCost, 25000, accuracy: 0.001)
        
        viewContext.delete(cashPosition)
        portfolio.updatedAt = Date()
        
        try viewContext.save()
        
        let afterPositionsCount = portfolio.positions?.count ?? -1
        let afterTotalValue = portfolio.totalValue
        let afterTotalCost = portfolio.totalCost
        let afterProfitLoss = portfolio.totalProfitLoss
        
        XCTAssertEqual(afterPositionsCount, 1, "positions.count should be 1 after delete")
        XCTAssertEqual(afterTotalValue, 20000, accuracy: 0.001, "totalValue should be 20000 after delete")
        XCTAssertEqual(afterTotalCost, 15000, accuracy: 0.001, "totalCost should be 15000 after delete")
        XCTAssertEqual(afterProfitLoss, 5000, accuracy: 0.001, "profitLoss should still be 5000")
    }
    
    func testEditCashAmount_updatesPortfolioMetrics() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let cashPosition = Position(context: viewContext)
        cashPosition.id = UUID()
        cashPosition.symbol = ""
        cashPosition.name = "现金"
        cashPosition.assetTypeRaw = AssetType.cash.rawValue
        cashPosition.shares = 10000
        cashPosition.costBasis = 1.0
        cashPosition.currentPrice = 1.0
        cashPosition.portfolio = portfolio
        
        try viewContext.save()
        
        let beforeTotalValue = portfolio.totalValue
        let beforeTotalCost = portfolio.totalCost
        
        XCTAssertEqual(beforeTotalValue, 10000, accuracy: 0.001)
        XCTAssertEqual(beforeTotalCost, 10000, accuracy: 0.001)
        
        cashPosition.shares = 20000
        portfolio.updatedAt = Date()
        
        try viewContext.save()
        
        let afterTotalValue = portfolio.totalValue
        let afterTotalCost = portfolio.totalCost
        
        XCTAssertEqual(afterTotalValue, 20000, accuracy: 0.001, "totalValue should be 20000 after edit")
        XCTAssertEqual(afterTotalCost, 20000, accuracy: 0.001, "totalCost should be 20000 after edit")
    }
    
    func testRefreshAllObjects_afterCashPositionChange() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        let cashPosition = Position(context: viewContext)
        cashPosition.id = UUID()
        cashPosition.symbol = ""
        cashPosition.name = "现金"
        cashPosition.assetTypeRaw = AssetType.cash.rawValue
        cashPosition.shares = 10000
        cashPosition.costBasis = 1.0
        cashPosition.currentPrice = 1.0
        cashPosition.portfolio = portfolio
        
        portfolio.updatedAt = Date()
        
        try viewContext.save()
        
        viewContext.refreshAllObjects()
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolios = try viewContext.fetch(request)
        let refreshedPortfolio = fetchedPortfolios.first!
        
        XCTAssertEqual(refreshedPortfolio.positions?.count, 1, "Should have 1 position after refresh")
        XCTAssertEqual(refreshedPortfolio.totalValue, 10000, "totalValue should be 10000 after refresh")
    }
    
    func testDeleteAllCashAndReAdd_updatesPortfolioCorrectly() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        var cashPosition = Position(context: viewContext)
        cashPosition.id = UUID()
        cashPosition.symbol = ""
        cashPosition.name = "现金"
        cashPosition.assetTypeRaw = AssetType.cash.rawValue
        cashPosition.shares = 10000
        cashPosition.costBasis = 1.0
        cashPosition.currentPrice = 1.0
        cashPosition.portfolio = portfolio
        
        portfolio.updatedAt = Date()
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Should have 1 position after add")
        XCTAssertEqual(portfolio.totalValue, 10000, "totalValue should be 10000")
        
        let cashPositions = (portfolio.positions as? Set<Position>)?.filter { $0.assetType == .cash } ?? []
        
        for pos in cashPositions {
            viewContext.delete(pos)
        }
        
        portfolio.updatedAt = Date()
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 0, "Should have 0 positions after delete")
        XCTAssertEqual(portfolio.totalValue, 0, "totalValue should be 0")
        
        cashPosition = Position(context: viewContext)
        cashPosition.id = UUID()
        cashPosition.symbol = ""
        cashPosition.name = "现金"
        cashPosition.assetTypeRaw = AssetType.cash.rawValue
        cashPosition.shares = 10000
        cashPosition.costBasis = 1.0
        cashPosition.currentPrice = 1.0
        cashPosition.portfolio = portfolio
        
        portfolio.updatedAt = Date()
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Should have 1 position after re-add")
        XCTAssertEqual(portfolio.totalValue, 10000, "totalValue should be 10000 after re-add")
        XCTAssertEqual(portfolio.totalCost, 10000, "totalCost should be 10000 after re-add")
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        let fetchedPortfolios = try viewContext.fetch(request)
        let fetchedPortfolio = fetchedPortfolios.first!
        
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Fetched portfolio should have 1 position")
        XCTAssertEqual(fetchedPortfolio.totalValue, 10000, "Fetched portfolio totalValue should be 10000")
    }
    
    func testDeleteAllCashAndReAdd_withRefreshAllObjects() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let portfolioId = portfolio.id!
        
        var cashPosition = Position(context: viewContext)
        cashPosition.id = UUID()
        cashPosition.symbol = ""
        cashPosition.name = "现金"
        cashPosition.assetTypeRaw = AssetType.cash.rawValue
        cashPosition.shares = 10000
        cashPosition.costBasis = 1.0
        cashPosition.currentPrice = 1.0
        cashPosition.portfolio = portfolio
        
        try viewContext.save()
        
        let cashPositions = (portfolio.positions as? Set<Position>)?.filter { $0.assetType == .cash } ?? []
        for pos in cashPositions {
            viewContext.delete(pos)
        }
        try viewContext.save()
        
        cashPosition = Position(context: viewContext)
        cashPosition.id = UUID()
        cashPosition.symbol = ""
        cashPosition.name = "现金"
        cashPosition.assetTypeRaw = AssetType.cash.rawValue
        cashPosition.shares = 10000
        cashPosition.costBasis = 1.0
        cashPosition.currentPrice = 1.0
        cashPosition.portfolio = portfolio
        
        portfolio.updatedAt = Date()
        try viewContext.save()
        
        viewContext.refreshAllObjects()
        
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolioId as CVarArg)
        let fetchedPortfolios = try viewContext.fetch(request)
        let refreshedPortfolio = fetchedPortfolios.first!
        
        XCTAssertEqual(refreshedPortfolio.positions?.count, 1, "Should have 1 position after refresh")
        XCTAssertEqual(refreshedPortfolio.totalValue, 10000, "totalValue should be 10000 after refresh")
    }
    
    // MARK: - Bug Reproduction Tests
    
    func testBug_PositionCreate_updatesPortfolioPositions() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 0, "Initial: should have 0 positions")
        
        let position = Position.create(
            in: viewContext,
            symbol: "018344",
            name: "Test Fund",
            assetType: .fund,
            market: .cn,
            shares: 1000,
            costBasis: 1.0,
            portfolio: portfolio
        )
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1, "portfolio.positions should have 1 position after save")
    }
    
    func testBug_AddMultiplePositions_portfolioPositionsCount() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let position1 = Position.create(
            in: viewContext,
            symbol: "018344",
            name: "Fund 1",
            assetType: .fund,
            market: .cn,
            shares: 1000,
            costBasis: 1.0,
            portfolio: portfolio
        )
        
        try viewContext.save()
        
        XCTAssertEqual(portfolio.positions?.count, 1)
        
        let position2 = Position.create(
            in: viewContext,
            symbol: "018345",
            name: "Fund 2",
            assetType: .fund,
            market: .cn,
            shares: 2000,
            costBasis: 1.0,
            portfolio: portfolio
        )
        
        portfolio.updatedAt = Date()
        try viewContext.save()
        
        let request = Position.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@", portfolio)
        let fetchedPositions = try viewContext.fetch(request)
        
        XCTAssertEqual(fetchedPositions.count, 2, "Fetch request should return 2 positions")
        XCTAssertEqual(portfolio.positions?.count, 2, "portfolio.positions should have 2 positions")
    }
    
    func testBug_RefreshData_portfolioPositionsCache() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position1 = Position.create(
            in: viewContext,
            symbol: "018344",
            name: "Fund 1",
            assetType: .fund,
            market: .cn,
            shares: 1000,
            costBasis: 1.0,
            portfolio: portfolio
        )
        
        try viewContext.save()
        
        viewContext.refresh(portfolio, mergeChanges: false)
        
        let positionsAfterRefresh = portfolio.positions as? Set<Position> ?? []
        
        for pos in positionsAfterRefresh {
            viewContext.refresh(pos, mergeChanges: false)
        }
        
        let position2 = Position.create(
            in: viewContext,
            symbol: "018345",
            name: "Fund 2",
            assetType: .fund,
            market: .cn,
            shares: 2000,
            costBasis: 1.0,
            portfolio: portfolio
        )
        
        portfolio.updatedAt = Date()
        try viewContext.save()
        
        let request = Position.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@", portfolio)
        let fetchedPositions = try viewContext.fetch(request)
        
        XCTAssertEqual(fetchedPositions.count, 2, "Fetch request should return 2 positions")
        XCTAssertEqual(portfolio.positions?.count, 2, "portfolio.positions should have 2 positions after refreshData + add")
    }
    
    func testBug_AddPositionWithTransaction_portfolioPositionsMismatch() throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let viewModel = PortfolioDetailViewModel(context: viewContext)
        viewModel.setPortfolio(portfolio)
        
        try viewModel.addPositionWithTransaction(
            symbol: "018344",
            name: "Test Fund 1",
            assetType: .fund,
            market: .cn,
            shares: 1000,
            costBasis: 1.0
        )
        
        XCTAssertEqual(viewModel.positions.count, 1, "viewModel.positions should have 1 position")
        XCTAssertEqual(portfolio.positions?.count, 1, "portfolio.positions should have 1 position")
        
        try viewModel.addPositionWithTransaction(
            symbol: "018345",
            name: "Test Fund 2",
            assetType: .fund,
            market: .cn,
            shares: 2000,
            costBasis: 1.0
        )
        
        XCTAssertEqual(viewModel.positions.count, 2, "viewModel.positions should have 2 positions")
        XCTAssertEqual(portfolio.positions?.count, 2, "portfolio.positions should have 2 positions")
        
        try viewModel.addPositionWithTransaction(
            symbol: "018346",
            name: "Test Fund 3",
            assetType: .fund,
            market: .cn,
            shares: 3000,
            costBasis: 1.0
        )
        
        XCTAssertEqual(viewModel.positions.count, 3, "viewModel.positions should have 3 positions")
        XCTAssertEqual(portfolio.positions?.count, 3, "portfolio.positions should have 3 positions")
    }
}
