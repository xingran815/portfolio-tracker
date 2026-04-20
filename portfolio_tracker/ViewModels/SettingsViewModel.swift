//
//  SettingsViewModel.swift
//  portfolio_tracker
//
//  ViewModel for settings management
//

import SwiftUI
import os.log

/// ViewModel for managing app settings and API keys
@MainActor
@Observable
final class SettingsViewModel {
    
    // MARK: - Properties
    
    /// Alpha Vantage API key input
    var alphaVantageKeyInput = ""
    
    /// Kimi API key input
    var kimiKeyInput = ""
    
    /// Baidu Qianfan API key input
    var baiduqianfanKeyInput = ""
    
    /// SerpAPI API key input
    var serpAPIKeyInput = ""
    
    /// Whether Alpha Vantage key is configured
    var isAlphaVantageConfigured = false
    
    /// Whether Kimi API key is configured
    var isKimiConfigured = false
    
    /// Whether Baidu Qianfan API key is configured
    var isBaiduqianfanConfigured = false
    
    /// Whether SerpAPI API key is configured
    var isSerpAPIConfigured = false
    
    /// Validation status for Alpha Vantage
    var alphaVantageStatus: ValidationStatus = .unknown
    
    /// Validation status for Kimi
    var kimiStatus: ValidationStatus = .unknown
    
    /// Validation status for Baidu Qianfan
    var baiduqianfanStatus: ValidationStatus = .unknown
    
    /// Validation status for SerpAPI
    var serpAPIStatus: ValidationStatus = .unknown
    
    /// Selected LLM provider
    var selectedProvider: LLMProvider = .baiduqianfan
    
    /// Selected Baidu Qianfan model
    var selectedBaiduModel: BaiduQianfanService.Model = .kimi_k2_5
    
    /// Whether validation is in progress
    var isValidating = false
    
    /// Error message
    var errorMessage: String?
    
    /// Show error alert
    var showError = false
    
    /// Show success alert
    var showSuccess = false
    
    /// Success message
    var successMessage = ""
    
    /// Selected tab in settings
    var selectedTab: SettingsTab = .general
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case apiKeys = "API Keys"
        case about = "About"
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .apiKeys: return "key.fill"
            case .about: return "info.circle"
            }
        }
    }
    
    enum ValidationStatus: Sendable {
        case unknown
        case valid
        case invalid(String)
        case validating
    }
    
    // MARK: - Dependencies
    
    private let apiKeyManager = APIKeyManager.shared
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "SettingsViewModel")
    
    nonisolated deinit {}
    
    // MARK: - Initialization
    
    init() {
        Task {
            await loadAPIKeyStatus()
        }
    }
    
    // MARK: - Public Methods
    
    /// Loads current API key configuration status
    func loadAPIKeyStatus() async {
        isAlphaVantageConfigured = await apiKeyManager.hasKey(for: .alphaVantage)
        isKimiConfigured = await apiKeyManager.hasKey(for: .kimi)
        isBaiduqianfanConfigured = await apiKeyManager.hasKey(for: .baiduqianfan)
        isSerpAPIConfigured = await apiKeyManager.hasKey(for: .serpAPI)
        
        alphaVantageStatus = isAlphaVantageConfigured ? .valid : .unknown
        kimiStatus = isKimiConfigured ? .valid : .unknown
        baiduqianfanStatus = isBaiduqianfanConfigured ? .valid : .unknown
        serpAPIStatus = isSerpAPIConfigured ? .valid : .unknown
        
        // Load provider preference
        selectedProvider = await LLMServiceFactory.shared.getProvider()
        selectedBaiduModel = await LLMServiceFactory.shared.getBaiduQianfanModel()
        
        logger.info("API key status loaded - AlphaVantage: \(self.isAlphaVantageConfigured), Kimi: \(self.isKimiConfigured), Baidu Qianfan: \(self.isBaiduqianfanConfigured), SerpAPI: \(self.isSerpAPIConfigured)")
    }
    
    /// Saves Alpha Vantage API key
    func saveAlphaVantageKey() {
        let key = alphaVantageKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !key.isEmpty else {
            showError(message: "API key cannot be empty")
            return
        }
        
        Task {
            guard await apiKeyManager.isValidKeyFormat(key, for: .alphaVantage) else {
                await MainActor.run {
                    showError(message: "Invalid API key format")
                }
                return
            }
            
            do {
                try await apiKeyManager.saveKey(key, for: .alphaVantage)
                isAlphaVantageConfigured = true
                alphaVantageStatus = .valid
                alphaVantageKeyInput = ""
                showSuccess(message: "Alpha Vantage API key saved successfully")
                logger.info("Saved Alpha Vantage API key")
            } catch {
                logger.error("Failed to save Alpha Vantage key: \(error.localizedDescription)")
                showError(message: "Failed to save API key: \(error.localizedDescription)")
            }
        }
    }
    
    /// Saves Kimi API key
    func saveKimiKey() {
        let key = kimiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !key.isEmpty else {
            showError(message: "API key cannot be empty")
            return
        }
        
        Task {
            guard await apiKeyManager.isValidKeyFormat(key, for: .kimi) else {
                await MainActor.run {
                    showError(message: "Invalid API key format. Kimi keys should start with 'sk-'")
                }
                return
            }
            
            do {
                try await apiKeyManager.saveKey(key, for: .kimi)
                isKimiConfigured = true
                kimiStatus = .valid
                kimiKeyInput = ""
                showSuccess(message: "Kimi API key saved successfully")
                logger.info("Saved Kimi API key")
            } catch {
                logger.error("Failed to save Kimi key: \(error.localizedDescription)")
                showError(message: "Failed to save API key: \(error.localizedDescription)")
            }
        }
    }
    
    /// Deletes Alpha Vantage API key
    func deleteAlphaVantageKey() {
        Task {
            do {
                try await apiKeyManager.deleteKey(for: .alphaVantage)
                isAlphaVantageConfigured = false
                alphaVantageStatus = .unknown
                showSuccess(message: "Alpha Vantage API key removed")
                logger.info("Deleted Alpha Vantage API key")
            } catch {
                logger.error("Failed to delete Alpha Vantage key: \(error.localizedDescription)")
                showError(message: "Failed to remove API key")
            }
        }
    }
    
    /// Deletes Kimi API key
    func deleteKimiKey() {
        Task {
            do {
                try await apiKeyManager.deleteKey(for: .kimi)
                isKimiConfigured = false
                kimiStatus = .unknown
                showSuccess(message: "Kimi API key removed")
                logger.info("Deleted Kimi API key")
            } catch {
                logger.error("Failed to delete Kimi key: \(error.localizedDescription)")
                showError(message: "Failed to remove API key")
            }
        }
    }
    
    /// Validates Alpha Vantage API key by making a test request
    func validateAlphaVantageKey() {
        guard isAlphaVantageConfigured else {
            showError(message: "No API key configured")
            return
        }
        
        alphaVantageStatus = .validating
        isValidating = true
        
        Task {
            // Create AlphaVantageProvider and test with a known symbol
            let apiKeyManager = APIKeyManager.shared
            let provider = AlphaVantageProvider(apiKeyManager: apiKeyManager)
            
            do {
                // Try to fetch a well-known stock (AAPL) to validate the key
                let quote = try await provider.fetchQuote(symbol: "AAPL", market: .us)
                
                await MainActor.run {
                    alphaVantageStatus = .valid
                    isValidating = false
                    showSuccess(message: "Alpha Vantage API key is valid! Fetched AAPL at $\(String(format: "%.2f", quote.price))")
                }
            } catch DataProviderError.apiKeyMissing {
                await MainActor.run {
                    alphaVantageStatus = .invalid("API key not found")
                    isValidating = false
                    showError(message: "API key not found in keychain")
                }
            } catch DataProviderError.invalidAPIKey {
                await MainActor.run {
                    alphaVantageStatus = .invalid("Invalid API key")
                    isValidating = false
                    showError(message: "Invalid API key. Please check your Alpha Vantage API key.")
                }
            } catch DataProviderError.rateLimited {
                await MainActor.run {
                    alphaVantageStatus = .invalid("Rate limited")
                    isValidating = false
                    showError(message: "Rate limit exceeded. Please wait a moment before trying again.")
                }
            } catch {
                await MainActor.run {
                    alphaVantageStatus = .invalid("Validation failed")
                    isValidating = false
                    showError(message: "Validation failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Validates Kimi API key with actual API call
    func validateKimiKey() {
        guard isKimiConfigured else {
            showError(message: "No API key configured")
            return
        }
        
        kimiStatus = .validating
        isValidating = true
        
        Task {
            // Create a real Kimi service and validate the API key
            let apiKeyManager = APIKeyManager.shared
            let kimiService = KimiService(apiKeyManager: apiKeyManager)
            
            let result = await kimiService.validateAPIKey()
            
            await MainActor.run {
                isValidating = false
                
                switch result {
                case .valid:
                    kimiStatus = .valid
                    showSuccess(message: "Kimi API key is valid and working!")
                case .notConfigured:
                    kimiStatus = .invalid("API key not found")
                    showError(message: "API key not found in keychain")
                case .invalid:
                    kimiStatus = .invalid("Invalid API key")
                    showError(message: "Invalid API key. Please check your Kimi API key.")
                case .networkError(let message):
                    kimiStatus = .invalid("Network error")
                    showError(message: "Network error: \(message)")
                case .rateLimited:
                    kimiStatus = .invalid("Rate limited")
                    showError(message: "Rate limit exceeded. Please try again later.")
                case .serviceUnavailable:
                    kimiStatus = .invalid("Service unavailable")
                    showError(message: "Kimi service is temporarily unavailable")
                }
            }
        }
    }
    
    /// Saves Baidu Qianfan API key to keychain
    func saveBaiduqianfanKey() {
        let key = baiduqianfanKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !key.isEmpty else {
            showError(message: "Please enter a valid API key")
            return
        }
        
        Task {
            guard await apiKeyManager.isValidKeyFormat(key, for: .baiduqianfan) else {
                await MainActor.run {
                    showError(message: "Invalid API key format. Baidu Qianfan keys should start with 'bce-'")
                }
                return
            }
            
            do {
                try await apiKeyManager.saveKey(key, for: .baiduqianfan)
                isBaiduqianfanConfigured = true
                baiduqianfanStatus = .valid
                baiduqianfanKeyInput = ""
                showSuccess(message: "Baidu Qianfan API key saved successfully!")
            } catch {
                await MainActor.run {
                    showError(message: "Failed to save API key: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Deletes Baidu Qianfan API key from keychain
    func deleteBaiduqianfanKey() {
        Task {
            do {
                try await APIKeyManager.shared.deleteKey(for: .baiduqianfan)
                
                await MainActor.run {
                    isBaiduqianfanConfigured = false
                    baiduqianfanStatus = .unknown
                    showSuccess(message: "Baidu Qianfan API key removed")
                }
            } catch {
                await MainActor.run {
                    showError(message: "Failed to remove API key: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Validates Baidu Qianfan API key by making a test request
    func validateBaiduqianfanKey() {
        guard isBaiduqianfanConfigured else {
            showError(message: "No Baidu Qianfan API key configured")
            return
        }
        
        baiduqianfanStatus = .validating
        isValidating = true
        
        Task {
            let apiKeyManager = APIKeyManager.shared
            let baiduService = BaiduQianfanService(apiKeyManager: apiKeyManager, model: selectedBaiduModel)
            
            let result = await baiduService.validateAPIKey()
            
            await MainActor.run {
                isValidating = false
                
                switch result {
                case .valid:
                    baiduqianfanStatus = .valid
                    showSuccess(message: "Baidu Qianfan API key is valid and working!")
                case .notConfigured:
                    baiduqianfanStatus = .invalid("API key not found")
                    showError(message: "API key not found in keychain")
                case .invalid:
                    baiduqianfanStatus = .invalid("Invalid API key")
                    showError(message: "Invalid API key. Please check your Baidu Qianfan API key.")
                case .networkError(let message):
                    baiduqianfanStatus = .invalid("Network error")
                    showError(message: "Network error: \(message)")
                case .rateLimited:
                    baiduqianfanStatus = .invalid("Rate limited")
                    showError(message: "Rate limit exceeded. Please try again later.")
                case .serviceUnavailable:
                    baiduqianfanStatus = .invalid("Service unavailable")
                    showError(message: "Baidu Qianfan service is temporarily unavailable")
                }
            }
        }
    }
    
    /// Opens documentation URL for a service
    /// - Parameter service: API service type
    func openDocumentation(for service: APIService) {
        if let url = URL(string: service.documentationURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - SerpAPI API Key Management
    
    /// Saves SerpAPI API key to keychain
    func saveSerpAPIKey() {
        let key = serpAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !key.isEmpty else {
            showError(message: "Please enter a valid API key")
            return
        }
        
        Task {
            guard await apiKeyManager.isValidKeyFormat(key, for: .serpAPI) else {
                await MainActor.run {
                    showError(message: "Invalid API key format. SerpAPI keys should start with 'tvly-'")
                }
                return
            }
            
            do {
                try await apiKeyManager.saveKey(key, for: .serpAPI)
                isSerpAPIConfigured = true
                serpAPIStatus = .valid
                serpAPIKeyInput = ""
                showSuccess(message: "SerpAPI API key saved successfully!")
            } catch {
                await MainActor.run {
                    showError(message: "Failed to save API key: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Deletes SerpAPI API key from keychain
    func deleteSerpAPIKey() {
        Task {
            do {
                try await APIKeyManager.shared.deleteKey(for: .serpAPI)
                
                await MainActor.run {
                    isSerpAPIConfigured = false
                    serpAPIStatus = .unknown
                    showSuccess(message: "SerpAPI API key removed")
                }
            } catch {
                await MainActor.run {
                    showError(message: "Failed to remove API key: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Validates SerpAPI API key by making a test request (uses 1 credit)
    func validateSerpAPIKey() {
        guard isSerpAPIConfigured else {
            showError(message: "No SerpAPI API key configured")
            return
        }
        
        serpAPIStatus = .validating
        isValidating = true
        
        Task {
            // Use full validation with search (only when user explicitly validates)
            let result = await SerpAPIService.shared.validateAPIKeyWithSearch()
            
            await MainActor.run {
                isValidating = false
                
                switch result {
                case .valid:
                    serpAPIStatus = .valid
                    showSuccess(message: "SerpAPI API key is valid and working!")
                case .notConfigured:
                    serpAPIStatus = .invalid("Not configured")
                    showError(message: "API key not found in keychain")
                case .invalid:
                    serpAPIStatus = .invalid("Invalid")
                    showError(message: "Invalid API key. Check format (should start with 'tvly-')")
                case .networkError(let message):
                    serpAPIStatus = .invalid("Network error")
                    showError(message: "Network error: \(message)")
                case .rateLimited:
                    serpAPIStatus = .invalid("Rate limited")
                    showError(message: "Rate limit exceeded. Try again later.")
                case .serviceUnavailable:
                    serpAPIStatus = .invalid("Unavailable")
                    showError(message: "SerpAPI service temporarily unavailable")
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    private func showSuccess(message: String) {
        successMessage = message
        showSuccess = true
    }
}
