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
    
    /// Whether Alpha Vantage key is configured
    var isAlphaVantageConfigured = false
    
    /// Whether Kimi API key is configured
    var isKimiConfigured = false
    
    /// Validation status for Alpha Vantage
    var alphaVantageStatus: ValidationStatus = .unknown
    
    /// Validation status for Kimi
    var kimiStatus: ValidationStatus = .unknown
    
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
        
        alphaVantageStatus = isAlphaVantageConfigured ? .valid : .unknown
        kimiStatus = isKimiConfigured ? .valid : .unknown
        
        logger.info("API key status loaded - AlphaVantage: \(self.isAlphaVantageConfigured), Kimi: \(self.isKimiConfigured)")
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
    
    /// Opens documentation URL for a service
    /// - Parameter service: API service type
    func openDocumentation(for service: APIService) {
        if let url = URL(string: service.documentationURL) {
            NSWorkspace.shared.open(url)
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
