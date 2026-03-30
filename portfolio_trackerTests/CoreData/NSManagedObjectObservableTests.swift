//
//  NSManagedObjectObservableTests.swift
//  portfolio_trackerTests
//
//  Tests for NSManagedObject ObservableObject conformance
//

import XCTest
import CoreData
import Combine
@testable import portfolio_tracker

@MainActor
final class NSManagedObjectObservableTests: XCTestCase {
    
    var persistenceController: PersistenceController!
    var viewContext: NSManagedObjectContext!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        persistenceController = PersistenceController(inMemory: true)
        viewContext = persistenceController.viewContext
        cancellables = []
    }
    
    override func tearDown() async throws {
        persistenceController = nil
        viewContext = nil
        cancellables = nil
        try await super.tearDown()
    }
    
    // MARK: - ObservableObject Conformance Tests
    
    func testPortfolio_isObservableObject() {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        XCTAssertTrue(portfolio is any ObservableObject, "Portfolio should conform to ObservableObject")
    }
    
    func testPosition_isObservableObject() {
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        
        XCTAssertTrue(position is any ObservableObject, "Position should conform to ObservableObject")
    }
    
    // MARK: - Property Change Notification Tests
    
    func testPortfolio_nameChange_triggersObjectWillChange() async throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let expectation = XCTestExpectation(description: "objectWillChange received")
        
        portfolio.objectWillChange
            .sink {
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        portfolio.name = "Updated Portfolio"
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testPosition_sharesChange_triggersObjectWillChange() async throws {
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        
        try viewContext.save()
        
        let expectation = XCTestExpectation(description: "objectWillChange received")
        
        position.objectWillChange
            .sink {
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        position.shares = 200
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Relationship Change Notification Tests
    
    func testPortfolio_addPosition_triggersObjectWillChange() async throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let expectation = XCTestExpectation(description: "objectWillChange received on position change")
        
        portfolio.objectWillChange
            .sink {
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testPosition_setPortfolio_triggersObjectWillChange() async throws {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        
        try viewContext.save()
        
        let expectation = XCTestExpectation(description: "objectWillChange received")
        
        position.objectWillChange
            .sink {
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        position.portfolio = portfolio
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
