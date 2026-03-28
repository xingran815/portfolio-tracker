//
//  PortfolioListViewModel.swift
//  portfolio_tracker
//
//  ViewModel for portfolio list sidebar
//

import SwiftUI
import CoreData
import os.log

/// ViewModel for managing portfolio list
@MainActor
@Observable
final class PortfolioListViewModel {
    
    // MARK: - Properties
    
    /// Currently selected portfolio ID
    var selectedPortfolioId: UUID?
    
    /// Loading state
    var isLoading = false
    
    /// Error message
    var errorMessage: String?
    
    /// Show error alert
    var showError = false
    
    // MARK: - Dependencies
    
    let viewContext: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "PortfolioListViewModel")
    
    // MARK: - Initialization
    
    init(context: NSManagedObjectContext = PersistenceController.shared.viewContext) {
        self.viewContext = context
    }
    
    // MARK: - Public Methods
    
    /// Creates a new portfolio
    /// - Parameters:
    ///   - name: Portfolio name
    ///   - riskProfile: Risk tolerance
    func createPortfolio(name: String, riskProfile: RiskProfile = .moderate) {
        guard !name.isEmpty else {
            showError(message: "Portfolio name cannot be empty")
            return
        }
        
        let portfolio = Portfolio.create(in: viewContext, name: name, riskProfile: riskProfile)
        
        do {
            try viewContext.save()
            selectedPortfolioId = portfolio.id
            logger.info("Created portfolio: \(name)")
        } catch {
            logger.error("Failed to save portfolio: \(error.localizedDescription)")
            showError(message: "Failed to create portfolio")
        }
    }
    
    /// Creates a new portfolio from parsed configuration
    /// - Parameter config: Portfolio configuration from MDParser or CreatePortfolioView
    func createFromConfig(_ config: PortfolioConfig) {
        guard !config.name.isEmpty else {
            showError(message: "Portfolio name cannot be empty")
            return
        }
        
        // Create portfolio with config data
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = config.name
        portfolio.riskProfileRaw = (config.riskProfile ?? .moderate).rawValue
        portfolio.currencyRaw = (config.currency ?? .cny).rawValue
        portfolio.expectedReturn = config.expectedReturn ?? 0.08
        portfolio.maxDrawdown = config.maxDrawdown ?? 0.15
        portfolio.rebalancingFrequencyRaw = (config.rebalancingFrequency ?? .quarterly).rawValue
        portfolio.createdAt = Date()
        portfolio.updatedAt = Date()
        
        // Set target allocation if provided
        if let allocation = config.targetAllocation, !allocation.isEmpty {
            portfolio.targetAllocation = allocation
        }
        
        // Create positions if provided
        for positionConfig in config.positions {
            let position = Position(context: viewContext)
            position.id = UUID()
            position.symbol = positionConfig.symbol
            position.name = positionConfig.name
            position.assetTypeRaw = (positionConfig.assetType ?? .stock).rawValue
            position.marketRaw = (positionConfig.market ?? .us).rawValue
            position.shares = positionConfig.shares
            position.costBasis = positionConfig.costBasis ?? 0
            position.currentPrice = 0
            position.currency = (positionConfig.market ?? .us).currency
            position.lastUpdated = nil
            position.portfolio = portfolio
        }
        
        do {
            try viewContext.save()
            selectedPortfolioId = portfolio.id
            logger.info("Created portfolio from config: \(config.name) with \(config.positions.count) positions")
        } catch {
            logger.error("Failed to save portfolio: \(error.localizedDescription)")
            showError(message: "Failed to create portfolio")
        }
    }
    
    /// Deletes a portfolio
    /// - Parameter portfolio: Portfolio to delete
    func deletePortfolio(_ portfolio: Portfolio) {
        viewContext.delete(portfolio)
        
        do {
            try viewContext.save()
            
            if selectedPortfolioId == portfolio.id {
                selectedPortfolioId = nil
            }
            
            logger.info("Deleted portfolio: \(portfolio.name ?? "Unknown")")
        } catch {
            logger.error("Failed to delete portfolio: \(error.localizedDescription)")
            showError(message: "Failed to delete portfolio")
        }
    }
    
    // MARK: - Private Helpers
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
