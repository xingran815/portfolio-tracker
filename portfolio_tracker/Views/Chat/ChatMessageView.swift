//
//  ChatMessageView.swift
//  portfolio_tracker
//
//  Individual chat message bubble with markdown support
//

import SwiftUI

/// View for displaying a single chat message
struct ChatMessageView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatarView
            
            // Message content
            VStack(alignment: .leading, spacing: 4) {
                // Role label
                Text(roleLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                // Content
                messageContent
                    .textSelection(.enabled)
                
                // Timestamp
                Text(message.timestamp.formattedAsDateTime())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if isStreaming {
                typingIndicator
            }
        }
    }
    
    // MARK: - Subviews
    
    private var avatarView: some View {
        Image(systemName: avatarIcon)
            .font(.title3)
            .foregroundStyle(avatarColor)
            .frame(width: 32, height: 32)
            .background(avatarColor.opacity(0.15))
            .clipShape(Circle())
    }
    
    private var messageContent: some View {
        Group {
            switch message.role {
            case .user:
                Text(message.content)
                    .font(.body)
            case .assistant, .system:
                MarkdownText(text: message.content)
            }
        }
    }
    
    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .opacity(isStreaming ? 1 : 0.3)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: isStreaming
                    )
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
        .padding(8)
    }
    
    // MARK: - Computed Properties
    
    private var avatarIcon: String {
        switch message.role {
        case .user:
            return "person.fill"
        case .assistant:
            return "brain.head.profile"
        case .system:
            return "gearshape.fill"
        }
    }
    
    private var avatarColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .purple
        case .system:
            return .gray
        }
    }
    
    private var roleLabel: String {
        switch message.role {
        case .user:
            return "您"
        case .assistant:
            return "AI 助手"
        case .system:
            return "系统"
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.08)
        case .assistant:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color.gray.opacity(0.08)
        }
    }
}

// MARK: - Markdown Text

/// Simple markdown renderer for chat messages
struct MarkdownText: View {
    let text: String
    
    var body: some View {
        Text(attributedString)
            .font(.body)
    }
    
    private var attributedString: AttributedString {
        var result = AttributedString(text)
        
        // Bold: **text**
        applyBoldFormatting(to: &result)
        
        // Italic: *text*
        applyItalicFormatting(to: &result)
        
        // Code: `text`
        applyCodeFormatting(to: &result)
        
        return result
    }
    
    private func applyBoldFormatting(to string: inout AttributedString) {
        let pattern = "\\*\\*(.+?)\\*\\*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsString = NSString(string: String(string.characters))
        let matches = regex.matches(in: String(string.characters), options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches.reversed() {
            let range = match.range(at: 1)
            if let swiftRange = Range(range, in: string) {
                string[swiftRange].font = .body.bold()
            }
        }
        
        // Remove markdown syntax
        if let cleanRegex = try? NSRegularExpression(pattern: "\\*\\*", options: []) {
            let cleanMatches = cleanRegex.matches(in: String(string.characters), options: [], range: NSRange(location: 0, length: nsString.length))
            for match in cleanMatches.reversed() {
                if let swiftRange = Range(match.range, in: string) {
                    string.removeSubrange(swiftRange)
                }
            }
        }
    }
    
    private func applyItalicFormatting(to string: inout AttributedString) {
        let pattern = "\\*(.+?)\\*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsString = NSString(string: String(string.characters))
        let matches = regex.matches(in: String(string.characters), options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches.reversed() {
            let range = match.range(at: 1)
            if let swiftRange = Range(range, in: string) {
                string[swiftRange].font = .body.italic()
            }
        }
        
        // Remove markdown syntax (single asterisks that aren't part of bold)
        // This is simplified - in practice would need more careful handling
    }
    
    private func applyCodeFormatting(to string: inout AttributedString) {
        let pattern = "`(.+?)`"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsString = NSString(string: String(string.characters))
        let matches = regex.matches(in: String(string.characters), options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches.reversed() {
            let range = match.range(at: 1)
            if let swiftRange = Range(range, in: string) {
                string[swiftRange].font = .system(.body, design: .monospaced)
                string[swiftRange].backgroundColor = Color.gray.opacity(0.2)
            }
        }
        
        // Remove backticks
        if let cleanRegex = try? NSRegularExpression(pattern: "`", options: []) {
            let cleanMatches = cleanRegex.matches(in: String(string.characters), options: [], range: NSRange(location: 0, length: nsString.length))
            for match in cleanMatches.reversed() {
                if let swiftRange = Range(match.range, in: string) {
                    string.removeSubrange(swiftRange)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        ChatMessageView(message: ChatMessage(
            role: .assistant,
            content: "Hello! I can help you with:\n\n1. **Portfolio analysis**\n2. *Rebalancing* suggestions\n3. `Risk` assessment"
        ))
        
        ChatMessageView(message: ChatMessage(
            role: .user,
            content: "What should I do with my AAPL position?"
        ))
        
        ChatMessageView(
            message: ChatMessage(
                role: .assistant,
                content: "Let me analyze that..."
            ),
            isStreaming: true
        )
    }
    .padding()
    .frame(width: 400)
}
