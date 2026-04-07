//
//  KeychainStorage.swift
//  portfolio_tracker
//
//  Keychain-backed API key storage for production
//

import Foundation
import Security
import os.log

/// Keychain-backed storage for API keys (production)
actor KeychainStorage: APIKeyStorage {
    
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "KeychainStorage")
    private let service = "com.portfolio_tracker.apikeys"
    
    func save(_ key: String, for service: APIService) async throws {
        guard let keyData = key.data(using: .utf8) else {
            logger.error("Failed to encode key data for \(service.displayName)")
            throw APIKeyError.invalidKeyData
        }
        
        // Delete existing key first (to avoid duplicates)
        try? await delete(for: service)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: service.rawValue,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            logger.error("Failed to save key for \(service.displayName): \(status)")
            throw APIKeyError.invalidStatus(status)
        }
        
        logger.info("Successfully saved API key for \(service.displayName)")
    }
    
    func get(for service: APIService) async throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: service.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                logger.warning("API key not found for \(service.displayName)")
                throw APIKeyError.itemNotFound
            }
            logger.error("Failed to retrieve key for \(service.displayName): \(status)")
            throw APIKeyError.invalidStatus(status)
        }
        
        guard let keyData = result as? Data,
              let key = String(data: keyData, encoding: .utf8) else {
            logger.error("Failed to decode key data for \(service.displayName)")
            throw APIKeyError.invalidKeyData
        }
        
        return key
    }
    
    func delete(for service: APIService) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: service.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // errSecItemNotFound is acceptable (key didn't exist)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete key for \(service.displayName): \(status)")
            throw APIKeyError.invalidStatus(status)
        }
        
        logger.info("Successfully deleted API key for \(service.displayName)")
    }
    
    func exists(for service: APIService) async -> Bool {
        do {
            _ = try await get(for: service)
            return true
        } catch {
            return false
        }
    }
}
