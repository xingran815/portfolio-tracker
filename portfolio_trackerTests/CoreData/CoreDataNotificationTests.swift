//
//  CoreDataNotificationTests.swift
//  portfolio_trackerTests
//
//  Tests for CoreData notification system
//

import XCTest
import CoreData
import Combine
@testable import portfolio_tracker

@MainActor
final class CoreDataNotificationTests: XCTestCase {
    
    var container: NSPersistentContainer!
    var viewContext: NSManagedObjectContext!
    var cancellables: Set<AnyCancellable>!
    
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
        cancellables = []
    }
    
    override func tearDown() async throws {
        container = nil
        viewContext = nil
        cancellables = nil
        try await super.tearDown()
    }
    
    // MARK: - Insert Notification Tests
    
    func testInsertPosition_triggersInsertedNotification() async throws {
        print("🟢 TEST: testInsertPosition_triggersInsertedNotification")
        
        let expectation = XCTestExpectation(description: "Insert notification received")
        
        NotificationCenter.default.publisher(
            for: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .sink { notification in
            if let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
                let hasPosition = inserted.contains { $0 is Position }
                let hasPortfolio = inserted.contains { $0 is Portfolio }
                print("🟢 Notification: inserted \(inserted.count) objects, hasPosition=\(hasPosition), hasPortfolio=\(hasPortfolio)")
                if hasPosition {
                    expectation.fulfill()
                }
            }
        }
        .store(in: &cancellables)
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testInsertPortfolio_triggersInsertedNotification() async throws {
        print("🟢 TEST: testInsertPortfolio_triggersInsertedNotification")
        
        let expectation = XCTestExpectation(description: "Insert notification received")
        
        NotificationCenter.default.publisher(
            for: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .sink { notification in
            if let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
                let hasPortfolio = inserted.contains { $0 is Portfolio }
                print("🟢 Notification: inserted \(inserted.count) objects, hasPortfolio=\(hasPortfolio)")
                if hasPortfolio {
                    expectation.fulfill()
                }
            }
        }
        .store(in: &cancellables)
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Update Notification Tests
    
    func testUpdatePosition_triggersUpdatedNotification() async throws {
        print("🟢 TEST: testUpdatePosition_triggersUpdatedNotification")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.shares = 100
        position.portfolio = portfolio
        
        try viewContext.save()
        
        let expectation = XCTestExpectation(description: "Update notification received")
        
        NotificationCenter.default.publisher(
            for: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .sink { notification in
            if let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
                let hasPosition = updated.contains { $0 is Position }
                let hasPortfolio = updated.contains { $0 is Portfolio }
                print("🟢 Notification: updated \(updated.count) objects, hasPosition=\(hasPosition), hasPortfolio=\(hasPortfolio)")
                if hasPosition {
                    expectation.fulfill()
                }
            }
        }
        .store(in: &cancellables)
        
        position.shares = 200
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testUpdatePortfolio_triggersUpdatedNotification() async throws {
        print("🟢 TEST: testUpdatePortfolio_triggersUpdatedNotification")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let expectation = XCTestExpectation(description: "Update notification received")
        
        NotificationCenter.default.publisher(
            for: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .sink { notification in
            if let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
                let hasPortfolio = updated.contains { $0 is Portfolio }
                print("🟢 Notification: updated \(updated.count) objects, hasPortfolio=\(hasPortfolio)")
                if hasPortfolio {
                    expectation.fulfill()
                }
            }
        }
        .store(in: &cancellables)
        
        portfolio.name = "Updated Portfolio"
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Delete Notification Tests
    
    func testDeletePosition_triggersDeletedNotification() async throws {
        print("🟢 TEST: testDeletePosition_triggersDeletedNotification")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        let position = Position(context: viewContext)
        position.id = UUID()
        position.symbol = "AAPL"
        position.portfolio = portfolio
        
        try viewContext.save()
        
        let expectation = XCTestExpectation(description: "Delete notification received")
        
        NotificationCenter.default.publisher(
            for: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .sink { notification in
            if let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> {
                let hasPosition = deleted.contains { $0 is Position }
                print("🟢 Notification: deleted \(deleted.count) objects, hasPosition=\(hasPosition)")
                if hasPosition {
                    expectation.fulfill()
                }
            }
        }
        .store(in: &cancellables)
        
        viewContext.delete(position)
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testDeletePortfolio_triggersDeletedNotification() async throws {
        print("🟢 TEST: testDeletePortfolio_triggersDeletedNotification")
        
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = "Test Portfolio"
        
        try viewContext.save()
        
        let expectation = XCTestExpectation(description: "Delete notification received")
        
        NotificationCenter.default.publisher(
            for: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .sink { notification in
            if let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> {
                let hasPortfolio = deleted.contains { $0 is Portfolio }
                print("🟢 Notification: deleted \(deleted.count) objects, hasPortfolio=\(hasPortfolio)")
                if hasPortfolio {
                    expectation.fulfill()
                }
            }
        }
        .store(in: &cancellables)
        
        viewContext.delete(portfolio)
        try viewContext.save()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
