//
//  Position+CoreDataProperties.swift
//  portfolio_tracker
//
//  Created by Xingran on 09.03.26.
//
//

public import Foundation
public import CoreData


public typealias PositionCoreDataPropertiesSet = NSSet

extension Position {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Position> {
        return NSFetchRequest<Position>(entityName: "Position")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var symbol: String?
    @NSManaged public var name: String?
    @NSManaged public var assetTypeRaw: String?
    @NSManaged public var marketRaw: String?
    @NSManaged public var shares: Double
    @NSManaged public var costBasis: Double
    @NSManaged public var currentPrice: Double
    @NSManaged public var currency: String?
    @NSManaged public var entryModeRaw: String?
    @NSManaged public var lastUpdated: Date?
    @NSManaged public var portfolio: Portfolio?

}

extension Position : Identifiable {

}
