//
//  APIKeyManager.swift
//  portfolio_tracker
//
//  Secure API key storage using macOS Keychain
//

import Foundation
import Security
import os.log

/// Service types that require API keys
enum APIService: String, CaseIterable, Sendable {
    case alphaVantage = "com.portfolio_tracker.alphavantage"
    case kimi = "com.portfolio_tracker.kimi"
    
    var displayName: String {
        switch self {
        case .alphaVantage: return "Alpha Vantage"
        case .kimi: return "Kimi API"
        }
    }
    
    var documentationURL: String {
        switch self {
        case .alphaVantage: return "https://www.alphavantage.co/support/#api-key"
        case .kimi: return "https://platform.moonshot.cn/docs/api-keys"
        }
    }
    
    var documentationURLValue: URL? {
        URL(string: documentationURL)
    }
}

/// Errors that can occur during keychain operations
enum APIKeyError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidStatus(OSStatus)
    case invalidKeyData
    
    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "API key not found in keychain"
        case .duplicateItem:
            return "API key already exists"
        case .invalidStatus(let status):
            return "Keychain error: \(status)"
        case .invalidKeyData:
            return "Invalid key data"
        }
    }
}

/// Manages secure storage of API keys in macOS Keychain
///
/// Usage:
/// ```swift
/// // Save API key
/// try await APIKeyManager.shared.saveKey("your-api-key", for: .alphaVantage)
///
/// // Retrieve API key
/// let key = try await APIKeyManager.shared.getKey(for: .alphaVantage)
///
/// // Delete API key
/// try await APIKeyManager.shared.deleteKey(for: .alphaVantage)
///
/// // Check if key exists
/// let exists = await APIKeyManager.shared.hasKey(for: .alphaVantage)
/// ```
actor APIKeyManager {
    
    // MARK: - Properties
    
    /// Shared singleton instance
    static let shared = APIKeyManager()
    
    /// Logger for debugging
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "APIKeyManager")
    
    /// Service name for keychain items
    private let service = "com.portfolio_tracker.apikeys"
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Saves an API key to the keychain
    /// - Parameters:
    ///   - key: The API key to store
    ///   - serviceType: The service this key belongs to
    /// - Throws: APIKeyError if save fails
    func saveKey(_ key: String, for serviceType: APIService) async throws {
        guard let keyData = key.data(using: .utf8) else {
            logger.error("Failed to encode key data for \(serviceType.displayName)")
            throw APIKeyError.invalidKeyData
        }
        
        // Delete existing key first (to avoid duplicates)
        try? await deleteKey(for: serviceType)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serviceType.rawValue,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            logger.error("Failed to save key for \(serviceType.displayName): \(status)")
            throw APIKeyError.invalidStatus(status)
        }
        
        logger.info("Successfully saved API key for \(serviceType.displayName)")
    }
    
    /// Retrieves an API key from the keychain
    /// - Parameter serviceType: The service to get the key for
    /// - Returns: The stored API key
    /// - Throws: APIKeyError if retrieval fails
    func getKey(for serviceType: APIService) async throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serviceType.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                logger.warning("API key not found for \(serviceType.displayName)")
                throw APIKeyError.itemNotFound
            }
            logger.error("Failed to retrieve key for \(serviceType.displayName): \(status)")
            throw APIKeyError.invalidStatus(status)
        }
        
        guard let keyData = result as? Data,
              let key = String(data: keyData, encoding: .utf8) else {
            logger.error("Failed to decode key data for \(serviceType.displayName)")
            throw APIKeyError.invalidKeyData
        }
        
        return key
    }
    
    /// Deletes an API key from the keychain
    /// - Parameter serviceType: The service to delete the key for
    /// - Throws: APIKeyError if deletion fails
    func deleteKey(for serviceType: APIService) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serviceType.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // errSecItemNotFound is acceptable (key didn't exist)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete key for \(serviceType.displayName): \(status)")
            throw APIKeyError.invalidStatus(status)
        }
        
        logger.info("Successfully deleted API key for \(serviceType.displayName)")
    }
    
    /// Checks if an API key exists in the keychain
    /// - Parameter serviceType: The service to check
    /// - Returns: True if a key exists
    func hasKey(for serviceType: APIService) async -> Bool {
        do {
            _ = try await getKey(for: serviceType)
            return true
        } catch {
            return false
        }
    }
    
    /// Gets configuration status for all services
    /// - Returns: Dictionary of service to configuration status
    func getAllServiceStatus() async -> [APIService: Bool] {
        var status: [APIService: Bool] = [:]
        for service in APIService.allCases {
            status[service] = await hasKey(for: service)
        }
        return status
    }
    
    /// Validates an API key format (basic checks)
    /// - Parameters:
    ///   - key: The key to validate
    ///   - serviceType: The service type for specific validation
    /// - Returns: True if the key format appears valid
    func isValidKeyFormat(_ key: String, for serviceType: APIService) -> Bool {
        switch serviceType {
        case .alphaVantage:
            return key.count >= 10 && !key.contains(" ")
        case .kimi:
            return key.hasPrefix("sk-") && key.count > 20
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension APIKeyManager {
    /// Mock API key manager for previews and testing
    static var preview: APIKeyManager {
        get async {
            let manager = APIKeyManager()
            // Pre-populate with fake keys for previews
            try? await manager.saveKey("demo-alphavantage-key", for: .alphaVantage)
            try? await manager.saveKey("sk-demo-kimi-key-for-preview-only", for: .kimi)
            return manager
        }
    }
}
#endif
