//
//  Portfolio+CoreDataProperties.swift
//  portfolio_tracker
//
//  Created by Xingran on 09.03.26.
//
//

public import Foundation
public import CoreData


public typealias PortfolioCoreDataPropertiesSet = NSSet

extension Portfolio {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Portfolio> {
        return NSFetchRequest<Portfolio>(entityName: "Portfolio")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var currencyRaw: String?
    @NSManaged public var expectedReturn: Double
    @NSManaged public var id: UUID?
    @NSManaged public var maxDrawdown: Double
    @NSManaged public var name: String?
    @NSManaged public var rebalancingFrequencyRaw: String?
    @NSManaged public var riskProfileRaw: String?
    @NSManaged public var targetAllocationData: Data?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var positions: NSSet?
    @NSManaged public var transactions: NSSet?

}

extension Portfolio : Identifiable {

}
