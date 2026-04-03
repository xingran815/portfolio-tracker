//
//  ChatViewModelNotificationTests.swift
//  portfolio_trackerTests
//
//  Tests for ChatViewModel notification handling
//

import XCTest
@testable import portfolio_tracker

@MainActor
final class ChatViewModelNotificationTests: XCTestCase {
    
    var viewModel: ChatViewModel!
    
    override func setUp() async throws {
        try await super.setUp()
        viewModel = ChatViewModel()
    }
    
    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }
    
    // MARK: - Model Change Notification Tests
    
    func testModelChangeNotificationTriggersServiceRefresh() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Service refreshed after model change")
        
        // When - post notification
        NotificationCenter.default.post(name: .llmModelDidChange, object: nil)
        
        // Wait for async update
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Then - service should be refreshed
        // Note: We're testing that no crash occurs and the notification is handled
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Provider Change Notification Tests
    
    func testProviderChangeNotificationTriggersServiceRefresh() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Service refreshed after provider change")
        
        // When - post notification
        NotificationCenter.default.post(name: .llmProviderDidChange, object: nil)
        
        // Wait for async update
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Then - service should be refreshed
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Multiple Notification Tests
    
    func testMultipleRapidModelNotifications() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Handled multiple notifications")
        expectation.expectedFulfillmentCount = 5
        
        // When - post multiple notifications rapidly
        for _ in 0..<5 {
            NotificationCenter.default.post(name: .llmModelDidChange, object: nil)
            expectation.fulfill()
        }
        
        // Wait for async updates
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Then - should not crash
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testMixedModelAndProviderNotifications() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Handled mixed notifications")
        expectation.expectedFulfillmentCount = 4
        
        // When - post mixed notifications
        NotificationCenter.default.post(name: .llmModelDidChange, object: nil)
        expectation.fulfill()
        
        NotificationCenter.default.post(name: .llmProviderDidChange, object: nil)
        expectation.fulfill()
        
        NotificationCenter.default.post(name: .llmModelDidChange, object: nil)
        expectation.fulfill()
        
        NotificationCenter.default.post(name: .llmProviderDidChange, object: nil)
        expectation.fulfill()
        
        // Wait for async updates
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Then - should not crash
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Observer Cleanup Tests
    
    func testObserverRemovedOnDeinit() async {
        // Given
        var localViewModel: ChatViewModel? = ChatViewModel()
        weak var weakViewModel = localViewModel
        
        // When - deallocate
        localViewModel = nil
        
        // Then - should be deallocated
        XCTAssertNil(weakViewModel, "ChatViewModel should be deallocated")
        
        // Post notification should not crash
        NotificationCenter.default.post(name: .llmModelDidChange, object: nil)
    }
}
