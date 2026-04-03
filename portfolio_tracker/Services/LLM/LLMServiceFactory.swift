//
//  LLMServiceFactory.swift
//  portfolio_tracker
//
//  Factory for creating and managing LLM service instances
//

import Foundation
import os.log

/// LLM Provider options
enum LLMProvider: String, Sendable, CaseIterable {
    case kimi
    case baiduqianfan
}

/// Factory for creating and managing LLM service instances
/// Handles auto-switching between mock and real services based on API key availability
actor LLMServiceFactory {
    
    // MARK: - Properties
    
    static let shared = LLMServiceFactory()
    
    private var currentService: (any LLMServiceProtocol)?
    private var currentProvider: LLMProvider
    private var selectedBaiduModel: BaiduQianfanService.Model
    private let apiKeyManager: APIKeyManager
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "LLMServiceFactory")
    
    // UserDefaults keys
    private let providerKey = "llm_provider_preference"
    private let modelKey = "baiduqianfan_model_preference"
    
    // MARK: - Initialization
    
    private init(apiKeyManager: APIKeyManager = .shared) {
        self.apiKeyManager = apiKeyManager
        
        // Load provider preference (default to Baidu Qianfan)
        if let savedProvider = UserDefaults.standard.string(forKey: providerKey),
           let provider = LLMProvider(rawValue: savedProvider) {
            self.currentProvider = provider
        } else {
            self.currentProvider = .baiduqianfan
        }
        
        // Load model preference for Baidu Qianfan
        if let savedModel = UserDefaults.standard.string(forKey: modelKey),
           let model = BaiduQianfanService.Model(rawValue: savedModel) {
            self.selectedBaiduModel = model
        } else {
            self.selectedBaiduModel = .kimi_k2_5
        }
    }
    
    // MARK: - Provider Management
    
    /// Sets the LLM provider
    /// - Parameter provider: The provider to use
    func setProvider(_ provider: LLMProvider) {
        currentProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: providerKey)
        currentService = nil
        logger.info("Switched LLM provider to: \(provider.rawValue)")
    }
    
    /// Gets the current LLM provider
    /// - Returns: The current provider
    func getProvider() -> LLMProvider {
        currentProvider
    }
    
    /// Sets the Baidu Qianfan model
    /// - Parameter model: The model to use
    func setBaiduQianfanModel(_ model: BaiduQianfanService.Model) {
        selectedBaiduModel = model
        UserDefaults.standard.set(model.rawValue, forKey: modelKey)
        currentService = nil
        logger.info("Switched Baidu Qianfan model to: \(model.rawValue)")
    }
    
    /// Gets the selected Baidu Qianfan model
    /// - Returns: The selected model
    func getBaiduQianfanModel() -> BaiduQianfanService.Model {
        selectedBaiduModel
    }
    
    // MARK: - Public Methods
    
    /// Returns the appropriate LLM service based on provider and API key availability
    /// - Returns: LLMService instance based on provider and key availability
    func getService() async -> any LLMServiceProtocol {
        // Return cached service if available and provider hasn't changed
        if let service = currentService {
            return service
        }
        
        // Create new service based on provider
        let service: any LLMServiceProtocol
        
        switch currentProvider {
        case .kimi:
            let hasKey = await apiKeyManager.hasKey(for: .kimi)
            if hasKey {
                logger.info("Creating Kimi service")
                service = KimiService(apiKeyManager: apiKeyManager)
            } else {
                logger.info("Creating mock service (no Kimi API key)")
                service = MockLLMService()
            }
            
        case .baiduqianfan:
            let hasKey = await apiKeyManager.hasKey(for: .baiduqianfan)
            if hasKey {
                logger.info("Creating Baidu Qianfan service (model: \(self.selectedBaiduModel.rawValue))")
                service = BaiduQianfanService(apiKeyManager: apiKeyManager, model: selectedBaiduModel)
            } else {
                logger.info("Creating mock service (no Baidu Qianfan API key)")
                service = MockLLMService()
            }
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
    
    /// Forces creation of a Baidu Qianfan service
    /// - Parameter model: Optional model to use
    /// - Returns: BaiduQianfanService instance
    func createBaiduQianfanService(model: BaiduQianfanService.Model? = nil) -> BaiduQianfanService {
        let selectedModel = model ?? selectedBaiduModel
        logger.info("Creating Baidu Qianfan service (model: \(selectedModel.rawValue))")
        let service = BaiduQianfanService(apiKeyManager: apiKeyManager, model: selectedModel)
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
    /// - Returns: True if using a real service, false if using mock
    func isUsingRealAPI() async -> Bool {
        if let service = currentService {
            return !(service is MockLLMService)
        }
        
        // Check based on current provider and API key availability
        switch currentProvider {
        case .kimi:
            return await apiKeyManager.hasKey(for: .kimi)
        case .baiduqianfan:
            return await apiKeyManager.hasKey(for: .baiduqianfan)
        }
    }
    
    /// Refreshes the service based on current provider and API key status
    /// Call this after adding/removing API keys or switching providers
    func refreshService() async -> any LLMServiceProtocol {
        clearCache()
        return await getService()
    }
}

// MARK: - Convenience Extensions

extension LLMServiceFactory {
    /// Quick check if real LLM is available without creating a service
    /// - Returns: True if current provider has API key configured
    func isRealLLMAvailable() async -> Bool {
        switch currentProvider {
        case .kimi:
            return await apiKeyManager.hasKey(for: .kimi)
        case .baiduqianfan:
            return await apiKeyManager.hasKey(for: .baiduqianfan)
        }
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
