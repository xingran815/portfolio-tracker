//
//  ChatView.swift
//  portfolio_tracker
//
//  AI chat interface with portfolio context
//

import SwiftUI

/// Main chat view with AI assistant
struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var showingClearConfirmation = false
    @State private var showingContextInfo = false
    @State private var isWebSearchAvailable = false
    @Environment(\.scenePhase) private var scenePhase
    
    let portfolioData: PortfolioViewData?
    
    init(viewModel: ChatViewModel, portfolio: Portfolio? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.portfolioData = portfolio.map { PortfolioViewData.from($0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader
            
            Divider()
            
            // Messages
            messagesList
            
            Divider()
            
            // Input area
            inputArea
        }
        .onAppear {
            viewModel.setPortfolio(portfolioData)
            Task {
                isWebSearchAvailable = await viewModel.isWebSearchAvailable
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && oldPhase == .inactive {
                Task {
                    isWebSearchAvailable = await viewModel.isWebSearchAvailable
                }
            }
        }
        .onChange(of: portfolioData?.id) { _, _ in
            viewModel.setPortfolio(portfolioData)
        }
        .onDisappear {
            viewModel.saveChatHistory()
        }
        .alert("清除对话", isPresented: $showingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                viewModel.clearConversation()
            }
        } message: {
            Text("确定要清除所有对话历史吗？")
        }
        .sheet(isPresented: $showingContextInfo) {
            contextInfoSheet
        }
        .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "发生错误")
        }
    }
    
    // MARK: - Subviews
    
    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("AI 投资助手")
                        .font(.headline)
                    
                    // Mode indicator
                    if viewModel.isUsingRealAPI {
                        Label("已连接", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                            .help("已连接到 Kimi AI 服务")
                    } else {
                        Label("演示模式", systemImage: "testtube.2")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                            .help("当前使用模拟回复。请在设置中添加 Kimi API Key 以启用真实 AI 对话。")
                    }
                }
                
                if let portfolioData = portfolioData {
                    Text("上下文: \(portfolioData.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Context toggle
            Toggle(isOn: $viewModel.includePortfolioContext) {
                Image(systemName: viewModel.includePortfolioContext ? "doc.text.fill" : "doc.text")
            }
            .toggleStyle(.button)
            .help(viewModel.includePortfolioContext ? "已启用组合上下文" : "已禁用组合上下文")
            
            Button(action: { showingContextInfo = true }) {
                Image(systemName: "info.circle")
            }
            .help("查看上下文信息")
            
            Button(action: { showingClearConfirmation = true }) {
                Image(systemName: "trash")
            }
            .help("清除对话")
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.messages) { message in
                    ChatMessageView(
                        message: message,
                        isStreaming: viewModel.isLoading && 
                                    message.id == viewModel.messages.last?.id &&
                                    message.role == .assistant
                    )
                    .id(message.id)
                    .contextMenu {
                        Button("复制") {
                            viewModel.copyToClipboard(message)
                        }
                        
                        if message.role == .assistant {
                            Button("重新生成") {
                                viewModel.regenerateLastResponse()
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                if viewModel.isLoading {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }
    
    private var inputArea: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Web search toggle (only show if available)
                if isWebSearchAvailable {
                    Button {
                        viewModel.isWebSearchEnabled.toggle()
                    } label: {
                        Image(systemName: viewModel.isWebSearchEnabled ? 
                              "globe.badge.chevron.backward" : "globe")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(viewModel.isWebSearchEnabled ? .blue : .secondary)
                    .help(viewModel.isWebSearchEnabled ? 
                          "Web search enabled - Click to disable" : 
                          "Enable web search for this message")
                }
                
                TextField("输入消息...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !viewModel.inputText.isEmpty && !viewModel.isLoading {
                            viewModel.sendMessage()
                        }
                    }
                    .disabled(viewModel.isLoading)
                
                // Send or Cancel button based on loading state
                if viewModel.isLoading {
                    Button(action: { viewModel.cancelStreaming() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .help("停止生成")
                } else {
                    Button(action: { viewModel.sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(viewModel.inputText.isEmpty ? .secondary : Color.accentColor)
                    }
                    .disabled(viewModel.inputText.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            
            HStack {
                Text(viewModel.isLoading ? "AI 正在思考..." : "按 ⌘+Enter 发送")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if viewModel.isWebSearchEnabled && isWebSearchAvailable {
                    Text("• 网页搜索已启用")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var contextInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("组合上下文")
                            .font(.headline)
                        
                        if let portfolioData = portfolioData {
                            Text("当前对话已包含以下组合信息：")
                                .font(.subheadline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledContent("名称", value: portfolioData.name)
                                LabeledContent("总市值", value: portfolioData.totalValue.formattedAsCurrency())
                                LabeledContent("风险偏好", value: portfolioData.riskProfile.displayName)
                                LabeledContent("持仓数量", value: "\(portfolioData.positionCount)")
                            }
                            .padding()
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Text("未选择组合")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Group {
                        Text("关于上下文")
                            .font(.headline)
                        
                        Text("启用组合上下文后，AI 可以：")
                            .font(.subheadline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Label("分析您的资产配置", systemImage: "checkmark.circle.fill")
                            Label("检测再平衡需求", systemImage: "checkmark.circle.fill")
                            Label("提供个性化建议", systemImage: "checkmark.circle.fill")
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Group {
                        Text("对话历史")
                            .font(.headline)
                        
                        Text("对话历史会自动保存，并在您重新打开应用时恢复。每个组合有独立的对话历史。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("上下文信息")

            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showingContextInfo = false
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
    
    // MARK: - Helpers
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            // Always scroll to the last message
            if let lastId = viewModel.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let portfolio = Portfolio(context: context)
    portfolio.name = "示例组合"
    
    return ChatView(
        viewModel: ChatViewModel(),
        portfolio: portfolio
    )
    .frame(height: 600)
}
