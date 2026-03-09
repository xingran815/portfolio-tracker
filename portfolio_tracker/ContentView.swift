//
//  ContentView.swift
//  portfolio_tracker
//
//  Main content view
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        NavigationSplitView {
            Text("Portfolio List\n(Coming in Phase 6)")
                .navigationTitle("投资组合")
        } content: {
            Text("Portfolio Detail\n(Coming in Phase 6)")
        } detail: {
            Text("Analytics\n(Coming in Phase 6)")
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
