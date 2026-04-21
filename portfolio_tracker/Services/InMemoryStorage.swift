//
//  InMemoryStorage.swift
//  portfolio_tracker
//
//  In-memory API key storage for testing
//

import Foundation
import os.log

/// In-memory storage for API keys (testing only)
actor InMemoryStorage: APIKeyStorage {
    
    private var storage: [APIService: String] = [:]
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "InMemoryStorage")
    
    func save(_ key: String, for service: APIService) async throws {
        storage[service] = key
        logger.debug("Saved key for \(service.displayName) (test storage)")
    }
    
    func get(for service: APIService) async throws -> String {
        guard let key = storage[service] else {
            logger.debug("Key not found for \(service.displayName) (test storage)")
            throw APIKeyError.itemNotFound
        }
        return key
    }
    
    func delete(for service: APIService) async throws {
        storage.removeValue(forKey: service)
        logger.debug("Deleted key for \(service.displayName) (test storage)")
    }
    
    func exists(for service: APIService) async -> Bool {
        return storage[service] != nil
    }
    
    /// Clears all stored keys (useful for test cleanup)
    func clearAll() async {
        storage.removeAll()
    }
    
    /// Test helper: Get all stored keys (for inspection in tests)
    func getAllKeys() async -> [APIService: String] {
        return storage
    }
    
    /// Test helper: Get key count
    func keyCount() async -> Int {
        return storage.count
    }
}
