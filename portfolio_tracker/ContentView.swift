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
    
    // ViewModels
    @State private var listViewModel = PortfolioListViewModel()
    @State private var chatViewModel = ChatViewModel()
    
    // UI State
    @State private var showingSettingsWindow = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar: Portfolio list
            PortfolioListView(viewModel: listViewModel)
        } content: {
            // Content: Portfolio detail
            PortfolioDetailView(portfolio: listViewModel.selectedPortfolio)
        }         detail: {
            // Detail: Chat/Analytics
            ChatView(viewModel: chatViewModel, portfolio: listViewModel.selectedPortfolio)
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
        .onAppear {
            // Set up chat view model with initial portfolio
            if let selectedPortfolio = listViewModel.selectedPortfolio {
                chatViewModel.setPortfolio(selectedPortfolio)
            }
        }
        .onChange(of: listViewModel.selectedPortfolio?.id) { _, _ in
            // Update chat context when portfolio changes
            if let selectedPortfolio = listViewModel.selectedPortfolio {
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
