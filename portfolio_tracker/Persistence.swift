//
//  Persistence.swift
//  portfolio_tracker
//
//  CoreData persistence controller
//

import CoreData
import os.log

/// Manages CoreData stack and persistence
public final class PersistenceController {
    
    /// Shared singleton instance
    public static let shared = PersistenceController()
    
    /// Logger for debugging
    private static let logger = Logger(subsystem: "com.portfolio_tracker", category: "Persistence")
    
    /// Shared managed object model to avoid "Failed to find a unique match" errors
    /// when multiple PersistenceController instances are created
    public static let sharedModel: NSManagedObjectModel = {
        guard let modelURL = Bundle(for: Portfolio.self).url(forResource: "portfolio_tracker", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model")
        }
        return model
    }()
    
    /// CoreData persistent container
    public let container: NSPersistentContainer
    
    /// Main view context
    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }
    
    /// Initializes the persistence controller
    /// - Parameter inMemory: If true, uses in-memory store for testing
    public init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "portfolio_tracker", managedObjectModel: Self.sharedModel)
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { [weak container] description, error in
            if let error = error as NSError? {
                Self.logger.error("Failed to load persistent stores: \(error), \(error.userInfo)")
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
            
            Self.logger.info("Loaded persistent store: \(description.url?.absoluteString ?? "unknown")")
            
            // Configure context
            container?.viewContext.automaticallyMergesChangesFromParent = true
            container?.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }
    }
    
    /// Creates a new background context
    /// - Returns: Background NSManagedObjectContext
    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    /// Performs work on background context
    /// - Parameter block: Work to perform
    public func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            block(context)
        }
    }
    
    /// Saves view context if has changes
    /// - Throws: CoreData save error
    public func save() throws {
        let context = container.viewContext
        guard context.hasChanges else { return }
        
        do {
            try context.save()
            Self.logger.debug("Saved view context successfully")
        } catch {
            Self.logger.error("Failed to save context: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Async save operation
    public func saveAsync() async throws {
        try await container.viewContext.perform {
            try self.save()
        }
    }
}

// MARK: - Preview Support

extension PersistenceController {
    
    /// Controller for SwiftUI previews with sample data
    @MainActor
    public static var preview: PersistenceController {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        
        // Create sample portfolio
        let portfolio = Portfolio(context: context)
        portfolio.id = UUID()
        portfolio.name = "示例组合"
        portfolio.riskProfileRaw = RiskProfile.moderate.rawValue
        portfolio.expectedReturn = 0.10
        portfolio.maxDrawdown = 0.20
        portfolio.rebalancingFrequencyRaw = RebalancingFrequency.quarterly.rawValue
        portfolio.targetAllocationData = try? JSONEncoder().encode(["AAPL": 0.4, "VOO": 0.6])
        portfolio.createdAt = Date()
        portfolio.updatedAt = Date()
        
        // Create sample positions
        let aapl = Position(context: context)
        aapl.id = UUID()
        aapl.symbol = "AAPL"
        aapl.name = "Apple Inc."
        aapl.assetTypeRaw = AssetType.stock.rawValue
        aapl.marketRaw = Market.us.rawValue
        aapl.shares = 100
        aapl.costBasis = 150.0
        aapl.currentPrice = 175.0
        aapl.currency = "USD"
        aapl.lastUpdated = Date()
        aapl.portfolio = portfolio
        
        let voo = Position(context: context)
        voo.id = UUID()
        voo.symbol = "VOO"
        voo.name = "Vanguard S&P 500 ETF"
        voo.assetTypeRaw = AssetType.etf.rawValue
        voo.marketRaw = Market.us.rawValue
        voo.shares = 50
        voo.costBasis = 400.0
        voo.currentPrice = 420.0
        voo.currency = "USD"
        voo.lastUpdated = Date()
        voo.portfolio = portfolio
        
        // Create sample transaction
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.typeRaw = TransactionType.buy.rawValue
        transaction.symbol = "AAPL"
        transaction.shares = 100
        transaction.price = 150.0
        transaction.amount = 15000.0
        transaction.fees = 5.0
        transaction.date = Date()
        transaction.portfolio = portfolio
        
        do {
            try context.save()
        } catch {
            Self.logger.error("Preview setup error: \(error.localizedDescription)")
        }
        
        return controller
    }
}
