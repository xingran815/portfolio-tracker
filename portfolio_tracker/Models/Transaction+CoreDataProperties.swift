//
//  Transaction+CoreDataProperties.swift
//  portfolio_tracker
//
//  Created by Xingran on 09.03.26.
//
//

public import Foundation
public import CoreData


public typealias TransactionCoreDataPropertiesSet = NSSet

extension Transaction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Transaction> {
        return NSFetchRequest<Transaction>(entityName: "Transaction")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var typeRaw: String?
    @NSManaged public var symbol: String?
    @NSManaged public var shares: Double
    @NSManaged public var price: Double
    @NSManaged public var amount: Double
    @NSManaged public var fees: Double
    @NSManaged public var date: Date?
    @NSManaged public var notes: String?
    @NSManaged public var portfolio: Portfolio?

}

extension Transaction : Identifiable {

}
