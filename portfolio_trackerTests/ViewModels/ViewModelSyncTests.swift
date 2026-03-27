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
    
    // MARK: - Portfolio Total Value Update Tests (模拟左侧列表更新)
    
    func testAddPosition_updatesPortfolioTotalValue_sameInstance() throws {
        print("🔴 TEST: testAddPosition_updatesPortfolioTotalValue_sameInstance")
        print("🔴 This test simulates what PortfolioRowView sees when position is added")
        
        // 1. 创建 portfolio
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        print("🔴 Initial state (same instance):")
        print("🔴   portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        print("🔴   portfolio.totalValue = \(portfolio.totalValue)")
        
        XCTAssertEqual(portfolio.positions?.count, 0, "Initial: should have 0 positions")
        XCTAssertEqual(portfolio.totalValue, 0, "Initial: totalValue should be 0")
        
        // 2. 添加现金 position (模拟用户操作)
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
        
        print("🔴 After add (same portfolio instance):")
        print("🔴   portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        print("🔴   portfolio.totalValue = \(portfolio.totalValue)")
        print("🔴   portfolio.totalCost = \(portfolio.totalCost)")
        print("🔴   portfolio.profitLossPercentage = \(portfolio.profitLossPercentage)")
        
        // 3. 验证同一实例是否自动更新
        XCTAssertEqual(portfolio.positions?.count, 1, "Same instance should have 1 position after save")
        XCTAssertEqual(portfolio.totalValue, 10000, "Same instance should have totalValue = 10000")
    }
    
    func testAddPosition_updatesPortfolioTotalValue_refreshedInstance() throws {
        print("🔴 TEST: testAddPosition_updatesPortfolioTotalValue_refreshedInstance")
        print("🔴 This test simulates what happens if we refresh the portfolio")
        
        // 1. 创建 portfolio
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        // 2. 添加 position
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
        
        // 3. 模拟 @FetchRequest 重新获取数据
        let request = Portfolio.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", portfolio.id! as CVarArg)
        let fetchedPortfolios = try viewContext.fetch(request)
        let fetchedPortfolio = fetchedPortfolios.first!
        
        print("🔴 After re-fetch (simulating @FetchRequest update):")
        print("🔴   fetchedPortfolio.positions.count = \(fetchedPortfolio.positions?.count ?? -1)")
        print("🔴   fetchedPortfolio.totalValue = \(fetchedPortfolio.totalValue)")
        
        // 4. 验证
        XCTAssertEqual(fetchedPortfolio.positions?.count, 1, "Fetched portfolio should have 1 position")
        XCTAssertEqual(fetchedPortfolio.totalValue, 10000, "Fetched portfolio should have totalValue = 10000")
    }
    
    func testDeletePosition_updatesPortfolioTotalValue() throws {
        print("🔴 TEST: testDeletePosition_updatesPortfolioTotalValue")
        print("🔴 This test simulates what PortfolioRowView sees when position is deleted")
        
        // 1. 创建 portfolio + position
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
        
        print("🔴 Before delete:")
        print("🔴   portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        print("🔴   portfolio.totalValue = \(portfolio.totalValue)")
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Should have 1 position before delete")
        XCTAssertEqual(portfolio.totalValue, 10000, "totalValue should be 10000 before delete")
        
        // 2. 删除 position
        viewContext.delete(position)
        try viewContext.save()
        
        print("🔴 After delete (same portfolio instance):")
        print("🔴   portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        print("🔴   portfolio.totalValue = \(portfolio.totalValue)")
        
        // 3. 验证
        XCTAssertEqual(portfolio.positions?.count, 0, "Should have 0 positions after delete")
        XCTAssertEqual(portfolio.totalValue, 0, "totalValue should be 0 after delete")
    }
    
    func testMultiplePositionChanges_updatesPortfolioCorrectly() throws {
        print("🔴 TEST: testMultiplePositionChanges_updatesPortfolioCorrectly")
        
        // 1. 创建 portfolio
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        // 2. 添加第一个 position
        let pos1 = Position(context: viewContext)
        pos1.id = UUID()
        pos1.symbol = "CASH1"
        pos1.assetTypeRaw = AssetType.cash.rawValue
        pos1.shares = 5000
        pos1.costBasis = 1.0
        pos1.currentPrice = 1.0
        pos1.portfolio = portfolio
        
        try viewContext.save()
        
        print("🔴 After first add:")
        print("🔴   portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        print("🔴   portfolio.totalValue = \(portfolio.totalValue)")
        
        XCTAssertEqual(portfolio.totalValue, 5000, "totalValue should be 5000")
        
        // 3. 添加第二个 position
        let pos2 = Position(context: viewContext)
        pos2.id = UUID()
        pos2.symbol = "CASH2"
        pos2.assetTypeRaw = AssetType.cash.rawValue
        pos2.shares = 3000
        pos2.costBasis = 1.0
        pos2.currentPrice = 1.0
        pos2.portfolio = portfolio
        
        try viewContext.save()
        
        print("🔴 After second add:")
        print("🔴   portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        print("🔴   portfolio.totalValue = \(portfolio.totalValue)")
        
        XCTAssertEqual(portfolio.positions?.count, 2, "Should have 2 positions")
        XCTAssertEqual(portfolio.totalValue, 8000, "totalValue should be 8000")
        
        // 4. 删除第一个 position
        viewContext.delete(pos1)
        try viewContext.save()
        
        print("🔴 After delete first:")
        print("🔴   portfolio.positions.count = \(portfolio.positions?.count ?? -1)")
        print("🔴   portfolio.totalValue = \(portfolio.totalValue)")
        
        XCTAssertEqual(portfolio.positions?.count, 1, "Should have 1 position after delete")
        XCTAssertEqual(portfolio.totalValue, 3000, "totalValue should be 3000")
    }
    
    // MARK: - Simulating @FetchRequest behavior
    
    func testFetchRequest_simulation_portfolioFetchAfterPositionChange() throws {
        print("🟠 TEST: testFetchRequest_simulation_portfolioFetchAfterPositionChange")
        print("🟠 This test simulates what @FetchRequest does when Position changes")
        
        // 1. 创建 portfolio
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        // 2. 模拟 @FetchRequest 的初始查询
        var request = Portfolio.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        var fetchedPortfolios = try viewContext.fetch(request)
        
        print("🟠 Initial fetch (simulating @FetchRequest):")
        print("🟠   fetchedPortfolios.count = \(fetchedPortfolios.count)")
        print("🟠   first portfolio.positions.count = \(fetchedPortfolios.first?.positions?.count ?? -1)")
        print("🟠   first portfolio.totalValue = \(fetchedPortfolios.first?.totalValue ?? -1)")
        
        XCTAssertEqual(fetchedPortfolios.count, 1)
        XCTAssertEqual(fetchedPortfolios.first?.positions?.count, 0)
        
        // 3. 添加 position
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "CASH"
        position.assetTypeRaw = AssetType.cash.rawValue
        position.shares = 10000
        position.costBasis = 1.0
        position.currentPrice = 1.0
        position.portfolio = portfolio
        
        try viewContext.save()
        
        // 4. 再次模拟 @FetchRequest 查询（Position 变化后）
        // @FetchRequest 会重新查询吗？
        request = Portfolio.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        fetchedPortfolios = try viewContext.fetch(request)
        
        print("🟠 After position added - re-fetch portfolios:")
        print("🟠   fetchedPortfolios.count = \(fetchedPortfolios.count)")
        print("🟠   first portfolio.positions.count = \(fetchedPortfolios.first?.positions?.count ?? -1)")
        print("🟠   first portfolio.totalValue = \(fetchedPortfolios.first?.totalValue ?? -1)")
        
        // 5. 验证
        XCTAssertEqual(fetchedPortfolios.count, 1)
        XCTAssertEqual(fetchedPortfolios.first?.positions?.count, 1, "Re-fetched portfolio should have 1 position")
        XCTAssertEqual(fetchedPortfolios.first?.totalValue, 10000, "Re-fetched portfolio should have totalValue = 10000")
        
        // 关键问题：@FetchRequest 是否会自动重新查询？
        // 如果不会，就需要手动触发更新
    }
    
    func testFetchRequest_simulation_withPortfolioUpdate() throws {
        print("🟠 TEST: testFetchRequest_simulation_withPortfolioUpdate")
        print("🟠 This test verifies if updating portfolio.updatedAt triggers @FetchRequest refresh")
        
        // 1. 创建 portfolio
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        portfolio.updatedAt = Date()
        
        try viewContext.save()
        
        // 2. 初始查询
        var request = Portfolio.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        var fetchedPortfolios = try viewContext.fetch(request)
        let originalUpdatedAt = fetchedPortfolios.first?.updatedAt
        
        print("🟠 Initial fetch:")
        print("🟠   updatedAt = \(originalUpdatedAt ?? Date.distantPast)")
        
        // 3. 添加 position + 更新 portfolio.updatedAt
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "CASH"
        position.assetTypeRaw = AssetType.cash.rawValue
        position.shares = 10000
        position.costBasis = 1.0
        position.currentPrice = 1.0
        position.portfolio = portfolio
        
        portfolio.updatedAt = Date()  // 关键：更新 portfolio 属性
        
        try viewContext.save()
        
        // 4. 再次查询
        request = Portfolio.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        fetchedPortfolios = try viewContext.fetch(request)
        let newUpdatedAt = fetchedPortfolios.first?.updatedAt
        
        print("🟠 After add + update updatedAt:")
        print("🟠   updatedAt = \(newUpdatedAt ?? Date.distantPast)")
        print("🟠   positions.count = \(fetchedPortfolios.first?.positions?.count ?? -1)")
        print("🟠   totalValue = \(fetchedPortfolios.first?.totalValue ?? -1)")
        
        // 5. 验证
        XCTAssertNotEqual(originalUpdatedAt, newUpdatedAt, "updatedAt should have changed")
        XCTAssertEqual(fetchedPortfolios.first?.positions?.count, 1)
        XCTAssertEqual(fetchedPortfolios.first?.totalValue, 10000)
    }
}
