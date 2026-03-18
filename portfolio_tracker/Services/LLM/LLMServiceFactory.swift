//
//  LLMServiceFactory.swift
//  portfolio_tracker
//
//  Factory for creating and managing LLM service instances
//

import Foundation
import os.log

// Import required types from other files
// Note: In a real project, these would be in separate modules or properly imported

/// Factory for creating and managing LLM service instances
/// Handles auto-switching between mock and real services based on API key availability
actor LLMServiceFactory {
    
    // MARK: - Properties
    
    static let shared = LLMServiceFactory()
    
    private var currentService: (any LLMServiceProtocol)?
    private let apiKeyManager: APIKeyManager
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "LLMServiceFactory")
    
    // MARK: - Initialization
    
    private init(apiKeyManager: APIKeyManager = .shared) {
        self.apiKeyManager = apiKeyManager
    }
    
    // MARK: - Public Methods
    
    /// Returns the appropriate LLM service based on API key availability
    /// - Returns: KimiService if API key exists, otherwise MockLLMService
    func getService() async -> any LLMServiceProtocol {
        // Return cached service if available
        if let service = currentService {
            // Check if we need to switch service type
            let hasRealKey = await apiKeyManager.hasKey(for: .kimi)
            let isUsingReal = !(service is MockLLMService)
            
            if hasRealKey && !isUsingReal {
                // Switch to real service
                logger.info("Switching from mock to real Kimi service")
                let newService = KimiService(apiKeyManager: apiKeyManager)
                currentService = newService
                return newService
            } else if !hasRealKey && isUsingReal {
                // Switch to mock service
                logger.info("Switching from real to mock service (no API key)")
                let newService = MockLLMService()
                currentService = newService
                return newService
            }
            
            return service
        }
        
        // Create new service based on API key availability
        let hasKey = await apiKeyManager.hasKey(for: .kimi)
        let service: any LLMServiceProtocol
        
        if hasKey {
            logger.info("Creating real Kimi service")
            service = KimiService(apiKeyManager: apiKeyManager)
        } else {
            logger.info("Creating mock LLM service")
            service = MockLLMService()
        }
        
        currentService = service
        return service
    }
    
    /// Forces creation of a real Kimi service (for testing or explicit switching)
    /// - Returns: KimiService instance
    func createRealService() async -> KimiService {
        logger.info("Creating real Kimi service (forced)")
        let service = KimiService(apiKeyManager: apiKeyManager)
        currentService = service
        return service
    }
    
    /// Forces creation of a mock service (for testing)
    /// - Returns: MockLLMService instance
    func createMockService() async -> MockLLMService {
        logger.info("Creating mock LLM service (forced)")
        let service = MockLLMService()
        currentService = service
        return service
    }
    
    /// Clears the cached service, forcing a new one to be created on next getService() call
    func clearCache() {
        logger.info("Clearing LLM service cache")
        currentService = nil
    }
    
    /// Checks if the current service is using a real API
    /// - Returns: True if using KimiService, false if using MockLLMService
    func isUsingRealAPI() async -> Bool {
        if let service = currentService {
            return !(service is MockLLMService)
        }
        // Check based on API key availability
        return await apiKeyManager.hasKey(for: .kimi)
    }
    
    /// Refreshes the service based on current API key status
    /// Call this after adding/removing API keys
    func refreshService() async -> any LLMServiceProtocol {
        clearCache()
        return await getService()
    }
}

// MARK: - Convenience Extensions

extension LLMServiceFactory {
    /// Quick check if real LLM is available without creating a service
    /// - Returns: True if Kimi API key is configured
    func isRealLLMAvailable() async -> Bool {
        await apiKeyManager.hasKey(for: .kimi)
    }
    
    /// Validates the current API key by making a test request
    /// - Returns: Validation result
    func validateCurrentAPIKey() async -> APIKeyValidationResult {
        guard await isRealLLMAvailable() else {
            return .notConfigured
        }
        
        let service = await getService()
        return await service.validateAPIKey()
    }
}
