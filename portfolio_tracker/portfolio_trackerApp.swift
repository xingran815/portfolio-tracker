//
//  portfolio_trackerApp.swift
//  portfolio_tracker
//
//  Created by Xingran on 09.03.26.
//

import SwiftUI
import CoreData

@main
struct portfolio_trackerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
