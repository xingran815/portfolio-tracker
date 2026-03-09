//
//  ChatView.swift
//  portfolio_tracker
//
//  AI chat interface with portfolio context
//

import SwiftUI

/// Main chat view with AI assistant
struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var showingClearConfirmation = false
    @State private var showingContextInfo = false
    
    let portfolio: Portfolio?
    
    init(portfolio: Portfolio? = nil) {
        self.portfolio = portfolio
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
            viewModel.setPortfolio(portfolio)
        }
        .onChange(of: portfolio?.id) { _, _ in
            viewModel.setPortfolio(portfolio)
        }
        .onDisappear {
            viewModel.saveChatHistory()
        }
        .alert("清除对话", isPresented: $showingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                viewModel.clearHistory()
            }
        } message: {
            Text("确定要清除所有对话历史吗？")
        }
        .sheet(isPresented: $showingContextInfo) {
            contextInfoSheet
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "发生错误")
        }
    }
    
    // MARK: - Subviews
    
    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 投资助手")
                    .font(.headline)
                
                if let portfolio = portfolio {
                    Text("上下文: \(portfolio.name ?? "未命名")")
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
                    ChatMessageView(message: message)
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
                
                // Streaming message
                if viewModel.isGenerating && !viewModel.streamingResponse.isEmpty {
                    ChatMessageView(
                        message: ChatMessage(
                            role: .assistant,
                            content: viewModel.streamingResponse
                        ),
                        isStreaming: true
                    )
                    .id("streaming")
                }
            }
            .listStyle(.plain)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.streamingResponse) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private var inputArea: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                TextField("输入消息...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !viewModel.inputText.isEmpty {
                            viewModel.sendMessage()
                        }
                    }
                
                Button(action: { viewModel.sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.inputText.isEmpty ? .secondary : Color.accentColor)
                }
                .disabled(viewModel.inputText.isEmpty || viewModel.isGenerating)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            
            HStack {
                Text(viewModel.isGenerating ? "AI 正在思考..." : "按 ⌘+Enter 发送")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if viewModel.isGenerating {
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
                        
                        if let portfolio = portfolio {
                            Text("当前对话已包含以下组合信息：")
                                .font(.subheadline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledContent("名称", value: portfolio.name ?? "-")
                                LabeledContent("总市值", value: portfolio.totalValue.formattedAsCurrency())
                                LabeledContent("风险偏好", value: portfolio.riskProfile.displayName)
                                let positionCount = (portfolio.positions as? Set<Position>)?.count ?? 0
                                LabeledContent("持仓数量", value: "\(positionCount)")
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
            if viewModel.isGenerating {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastId = viewModel.messages.last?.id {
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
    
    return ChatView(portfolio: portfolio)
        .frame(height: 600)
}
