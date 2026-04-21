//
//  APIKeyStorage.swift
//  portfolio_tracker
//
//  Protocol for API key storage abstraction
//  Allows different storage backends (keychain, in-memory, etc.)
//

import Foundation

/// Protocol for API key storage operations
/// Allows different storage backends (keychain, in-memory, etc.)
protocol APIKeyStorage: Sendable {
    /// Saves an API key
    /// - Parameters:
    ///   - key: The API key to store
    ///   - service: The service this key belongs to
    func save(_ key: String, for service: APIService) async throws
    
    /// Retrieves an API key
    /// - Parameter service: The service to get the key for
    /// - Returns: The stored API key
    /// - Throws: APIKeyError.itemNotFound if key doesn't exist
    func get(for service: APIService) async throws -> String
    
    /// Deletes an API key
    /// - Parameter service: The service to delete the key for
    func delete(for service: APIService) async throws
    
    /// Checks if an API key exists
    /// - Parameter service: The service to check
    /// - Returns: True if a key exists
    func exists(for service: APIService) async -> Bool
}
