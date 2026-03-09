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
    
    /// All portfolios
    var portfolios: [Portfolio] = []
    
    /// Currently selected portfolio ID
    var selectedPortfolioId: UUID?
    
    /// Loading state
    var isLoading = false
    
    /// Error message
    var errorMessage: String?
    
    /// Show error alert
    var showError = false
    
    // MARK: - Dependencies
    
    private let viewContext: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.portfolio_tracker", category: "PortfolioListViewModel")
    
    // MARK: - Initialization
    
    init(context: NSManagedObjectContext = PersistenceController.shared.viewContext) {
        self.viewContext = context
        loadPortfolios()
    }
    
    // MARK: - Public Methods
    
    /// Loads all portfolios from CoreData
    func loadPortfolios() {
        isLoading = true
        defer { isLoading = false }
        
        let request = Portfolio.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)]
        
        do {
            portfolios = try viewContext.fetch(request)
            logger.info("Loaded \(self.portfolios.count) portfolios")
        } catch {
            logger.error("Failed to fetch portfolios: \(error.localizedDescription)")
            showError(message: "Failed to load portfolios")
        }
    }
    
    /// Creates a new portfolio
    /// - Parameters:
    ///   - name: Portfolio name
    ///   - riskProfile: Risk tolerance
    func createPortfolio(name: String, riskProfile: RiskProfile = .moderate) {
        guard !name.isEmpty else {
            showError(message: "Portfolio name cannot be empty")
            return
        }
        
        // Check for duplicate name
        if portfolios.contains(where: { $0.name?.lowercased() == name.lowercased() }) {
            showError(message: "A portfolio with this name already exists")
            return
        }
        
        let portfolio = Portfolio.create(in: viewContext, name: name, riskProfile: riskProfile)
        
        do {
            try viewContext.save()
            portfolios.append(portfolio)
            selectedPortfolioId = portfolio.id
            logger.info("Created portfolio: \(name)")
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
            portfolios.removeAll { $0.id == portfolio.id }
            
            if selectedPortfolioId == portfolio.id {
                selectedPortfolioId = portfolios.first?.id
            }
            
            logger.info("Deleted portfolio: \(portfolio.name ?? "Unknown")")
        } catch {
            logger.error("Failed to delete portfolio: \(error.localizedDescription)")
            showError(message: "Failed to delete portfolio")
        }
    }
    
    /// Deletes portfolios at indices
    /// - Parameter offsets: IndexSet to delete
    func deletePortfolios(at offsets: IndexSet) {
        for index in offsets {
            let portfolio = portfolios[index]
            deletePortfolio(portfolio)
        }
    }
    
    /// Returns the selected portfolio
    var selectedPortfolio: Portfolio? {
        portfolios.first { $0.id == selectedPortfolioId }
    }
    
    // MARK: - Private Helpers
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
