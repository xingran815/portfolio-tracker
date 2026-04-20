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
    case baiduqianfan = "com.portfolio_tracker.baiduqianfan"
    case serpAPI = "com.portfolio_tracker.serpapi"
    
    var displayName: String {
        switch self {
        case .alphaVantage: return "Alpha Vantage"
        case .kimi: return "Kimi API"
        case .baiduqianfan: return "Baidu Qianfan"
        case .serpAPI: return "SerpAPI (Web Search)"
        }
    }
    
    var documentationURL: String {
        switch self {
        case .alphaVantage: return "https://www.alphavantage.co/support/#api-key"
        case .kimi: return "https://platform.moonshot.cn/docs/api-keys"
        case .baiduqianfan: return "https://console.bce.baidu.com/qianfan/resource/subscribe"
        case .serpAPI: return "https://serpapi.com"
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

/// Manages secure storage of API keys
///
/// Usage:
/// ```swift
/// // Save API key (production)
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
///
/// // For testing with in-memory storage
/// let testStorage = InMemoryStorage()
/// let testManager = APIKeyManager(storage: testStorage)
/// ```
actor APIKeyManager {
    
    // MARK: - Properties
    
    /// Shared singleton instance (uses keychain storage)
    static let shared = APIKeyManager(storage: KeychainStorage())
    
    /// Storage backend (keychain for production, in-memory for testing)
    private let storage: any APIKeyStorage
    
    /// Logger for debugging
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "APIKeyManager")
    
    // MARK: - Initialization
    
    /// Initialize with custom storage (for testing)
    /// - Parameter storage: Storage backend to use
    init(storage: any APIKeyStorage) {
        self.storage = storage
    }
    
    // MARK: - Public Methods
    
    /// Saves an API key
    /// - Parameters:
    ///   - key: The API key to store
    ///   - serviceType: The service this key belongs to
    /// - Throws: APIKeyError if save fails
    func saveKey(_ key: String, for serviceType: APIService) async throws {
        try await storage.save(key, for: serviceType)
        logger.info("Saved API key for \(serviceType.displayName)")
    }
    
    /// Retrieves an API key
    /// - Parameter serviceType: The service to get the key for
    /// - Returns: The stored API key
    /// - Throws: APIKeyError if retrieval fails
    func getKey(for serviceType: APIService) async throws -> String {
        return try await storage.get(for: serviceType)
    }
    
    /// Deletes an API key
    /// - Parameter serviceType: The service to delete the key for
    /// - Throws: APIKeyError if deletion fails
    func deleteKey(for serviceType: APIService) async throws {
        try await storage.delete(for: serviceType)
        logger.info("Deleted API key for \(serviceType.displayName)")
    }
    
    /// Checks if an API key exists
    /// - Parameter serviceType: The service to check
    /// - Returns: True if a key exists
    func hasKey(for serviceType: APIService) async -> Bool {
        return await storage.exists(for: serviceType)
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
        case .baiduqianfan:
            return key.hasPrefix("bce-") && key.count > 20
        case .serpAPI:
            return key.count >= 30
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension APIKeyManager {
    /// Mock API key manager for previews and testing
    static var preview: APIKeyManager {
        get async {
            let storage = InMemoryStorage()
            let manager = APIKeyManager(storage: storage)
            try? await manager.saveKey("demo-alphavantage-key", for: .alphaVantage)
            try? await manager.saveKey("sk-demo-kimi-key-for-preview-only", for: .kimi)
            try? await manager.saveKey("demo-serpapi-key-for-preview-only-1234567890", for: .serpAPI)
            return manager
        }
    }
}
#endif
