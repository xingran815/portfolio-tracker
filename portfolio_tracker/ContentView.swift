//
//  ContentView.swift
//  portfolio_tracker
//
//  Main content view with NavigationSplitView
//

import SwiftUI
import CoreData

/// Main application content view with three-column layout
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Portfolio.name)],
        animation: .default
    )
    private var portfolios: FetchedResults<Portfolio>
    
    // ViewModels
    @State private var listViewModel = PortfolioListViewModel()
    @State private var chatViewModel = ChatViewModel()
    
    // UI State
    @State private var showingSettingsWindow = false
    
    var selectedPortfolio: Portfolio? {
        guard let id = listViewModel.selectedPortfolioId else { return nil }
        return portfolios.first { $0.id == id }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar: Portfolio list
            PortfolioListView(viewModel: listViewModel)
        } content: {
            // Content: Portfolio detail
            PortfolioDetailView(portfolio: selectedPortfolio)
        }         detail: {
            // Detail: Chat/Analytics
            ChatView(viewModel: chatViewModel, portfolio: selectedPortfolio)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingSettingsWindow) {
            SettingsWindow()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { showingSettingsWindow = true }) {
                    Image(systemName: "gear")
                }
                .help("设置")
            }
        }
        .onChange(of: listViewModel.selectedPortfolioId) { _, _ in
            // Update chat context when portfolio changes
            if let selectedPortfolio = selectedPortfolio {
                chatViewModel.setPortfolio(selectedPortfolio)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
