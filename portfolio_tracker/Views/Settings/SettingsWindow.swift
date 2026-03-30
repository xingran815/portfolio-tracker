//
//  SettingsWindow.swift
//  portfolio_tracker
//
//  Separate settings window for app configuration
//

import SwiftUI

/// Standalone settings window
struct SettingsWindow: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            settingsSidebar
        } detail: {
            // Detail view based on selection
            settingsDetail
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "发生错误")
        }
        .alert("成功", isPresented: $viewModel.showSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.successMessage)
        }
    }
    
    // MARK: - Sidebar
    
    private var settingsSidebar: some View {
        List(selection: $viewModel.selectedTab) {
            Section("设置") {
                ForEach(SettingsViewModel.SettingsTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("设置")
        .frame(minWidth: 150)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Detail Views
    
    @ViewBuilder
    private var settingsDetail: some View {
        switch viewModel.selectedTab {
        case .general:
            generalSettingsView
        case .apiKeys:
            apiKeysSettingsView
        case .about:
            aboutSettingsView
        }
    }
    
    // MARK: - General Settings
    
    private var generalSettingsView: some View {
        Form {
            Section("数据") {
                LabeledContent("数据存储", value: "本地 CoreData")
                
                Button("清除所有数据") {
                    // Show confirmation dialog
                }
                .foregroundStyle(.red)
            }
            
            Section("缓存") {
                LabeledContent("价格缓存", value: "1 天")
                
                Button("清除缓存") {
                    // Clear price cache
                }
            }
            
            Section("导出") {
                Button("导出投资组合数据...") {
                    // Export functionality
                }
                
                Button("导入投资组合数据...") {
                    // Import functionality
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsViewModel.SettingsTab.general.rawValue)
    }
    
    // MARK: - API Keys Settings
    
    private var apiKeysSettingsView: some View {
        Form {
            alphaVantageSection
            
            Divider()
                .padding(.vertical, 8)
            
            kimiSection
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsViewModel.SettingsTab.apiKeys.rawValue)
    }
    
    private var alphaVantageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alpha Vantage")
                            .font(.headline)
                        Text("美股、港股价格数据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    StatusIndicator(status: viewModel.alphaVantageStatus)
                }
                
                // Status
                HStack {
                    Text("状态:")
                        .foregroundStyle(.secondary)
                    
                    if viewModel.isAlphaVantageConfigured {
                        Label("已配置", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("未配置", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    
                    Spacer()
                    
                    if let url = APIService.alphaVantage.documentationURLValue {
                        Link(destination: url) {
                            Text("获取 API Key →")
                                .font(.caption)
                        }
                    }
                }
                
                // Input field (only show if not configured or editing)
                if !viewModel.isAlphaVantageConfigured {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("输入 API Key", text: $viewModel.alphaVantageKeyInput)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Text("您的 API Key 将安全存储在 macOS 钥匙串中")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button("保存") {
                                viewModel.saveAlphaVantageKey()
                            }
                            .disabled(viewModel.alphaVantageKeyInput.isEmpty)
                        }
                    }
                } else {
                    // Actions for configured state
                    HStack {
                        Button("验证") {
                            viewModel.validateAlphaVantageKey()
                        }
                        .disabled(viewModel.isValidating)
                        
                        Button("删除") {
                            viewModel.deleteAlphaVantageKey()
                        }
                        .foregroundStyle(.red)
                        
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var kimiSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.largeTitle)
                        .foregroundStyle(.purple)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kimi API")
                            .font(.headline)
                        Text("AI 投资助手")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    StatusIndicator(status: viewModel.kimiStatus)
                }
                
                // Status
                HStack {
                    Text("状态:")
                        .foregroundStyle(.secondary)
                    
                    if viewModel.isKimiConfigured {
                        Label("已配置", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("未配置（可选）", systemImage: "minus.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    
                    Spacer()
                    
                    if let url = APIService.kimi.documentationURLValue {
                        Link(destination: url) {
                            Text("获取 API Key →")
                                .font(.caption)
                        }
                    }
                }
                
                // Input field
                if !viewModel.isKimiConfigured {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("输入 API Key (sk-...)", text: $viewModel.kimiKeyInput)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Text("您的 API Key 将安全存储在 macOS 钥匙串中")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button("保存") {
                                viewModel.saveKimiKey()
                            }
                            .disabled(viewModel.kimiKeyInput.isEmpty)
                        }
                    }
                } else {
                    // Actions for configured state
                    HStack {
                        Button("验证") {
                            viewModel.validateKimiKey()
                        }
                        .disabled(viewModel.isValidating)
                        
                        Button("删除") {
                            viewModel.deleteKimiKey()
                        }
                        .foregroundStyle(.red)
                        
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - About Settings
    
    private var aboutSettingsView: some View {
        VStack(spacing: 24) {
            // App icon placeholder
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("PortfolioTracker")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("版本 1.0.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 12) {
                Text("AI 驱动的投资组合管理工具")
                    .font(.headline)
                
                Text("帮助您跟踪投资组合、分析资产配置，并通过 AI 获取个性化的再平衡建议。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    if let githubURL = URL(string: "https://github.com/xingran815/portfolio-tracker") {
                        Link("GitHub", destination: githubURL)
                    }
                    if let issuesURL = URL(string: "https://github.com/xingran815/portfolio-tracker/issues") {
                        Link("反馈问题", destination: issuesURL)
                    }
                }
                
                Text("© 2026 PortfolioTracker. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(SettingsViewModel.SettingsTab.about.rawValue)
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let status: SettingsViewModel.ValidationStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private var color: Color {
        switch status {
        case .unknown:
            return .gray
        case .valid:
            return .green
        case .invalid:
            return .red
        case .validating:
            return .blue
        }
    }
    
    private var text: String {
        switch status {
        case .unknown:
            return "未验证"
        case .valid:
            return "有效"
        case .invalid:
            return "无效"
        case .validating:
            return "验证中..."
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsWindow()
}
