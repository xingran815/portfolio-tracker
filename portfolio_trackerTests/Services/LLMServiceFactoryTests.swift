//
//  LLMServiceFactoryTests.swift
//  portfolio_trackerTests
//
//  Tests for LLMServiceFactory notification posting
//

import XCTest
@testable import portfolio_tracker

final class LLMServiceFactoryTests: XCTestCase {
    
    // MARK: - Model Change Notification Tests
    
    func testSetBaiduQianfanModelPostsNotification() async {
        // Given
        var notificationReceived = false
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .llmModelDidChange,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
            expectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // When
        await LLMServiceFactory.shared.setBaiduQianfanModel(.glm5)
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationReceived, "Should post notification when model changes")
    }
    
    func testSetBaiduQianfanModelToKimiK25PostsNotification() async {
        // Given
        var notificationReceived = false
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .llmModelDidChange,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
            expectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // When
        await LLMServiceFactory.shared.setBaiduQianfanModel(.kimi_k2_5)
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationReceived, "Should post notification when model changes to kimi-k2.5")
    }
    
    func testSetBaiduQianfanModelToMinimaxM25PostsNotification() async {
        // Given
        var notificationReceived = false
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .llmModelDidChange,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
            expectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // When
        await LLMServiceFactory.shared.setBaiduQianfanModel(.minimax_m2_5)
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationReceived, "Should post notification when model changes to minimax-m2.5")
    }
    
    // MARK: - Provider Change Notification Tests
    
    func testSetProviderToBaiduQianfanPostsNotification() async {
        // Given
        var notificationReceived = false
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .llmProviderDidChange,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
            expectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // When
        await LLMServiceFactory.shared.setProvider(.baiduqianfan)
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationReceived, "Should post notification when provider changes to Baidu Qianfan")
    }
    
    func testSetProviderToKimiPostsNotification() async {
        // Given
        var notificationReceived = false
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .llmProviderDidChange,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
            expectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // When
        await LLMServiceFactory.shared.setProvider(.kimi)
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationReceived, "Should post notification when provider changes to Kimi")
    }
    
    // MARK: - Integration Tests
    
    func testGetBaiduQianfanModelReturnsLastSetModel() async {
        // When
        await LLMServiceFactory.shared.setBaiduQianfanModel(.glm5)
        let model = await LLMServiceFactory.shared.getBaiduQianfanModel()
        
        // Then
        XCTAssertEqual(model, .glm5, "Should return the last set model")
    }
    
    func testGetProviderReturnsLastSetProvider() async {
        // When
        await LLMServiceFactory.shared.setProvider(.baiduqianfan)
        let provider = await LLMServiceFactory.shared.getProvider()
        
        // Then
        XCTAssertEqual(provider, .baiduqianfan, "Should return the last set provider")
    }
}
