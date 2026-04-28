//
//  EmptyStateView.swift
//  portfolio_tracker
//
//  Consistent empty-state placeholder. Wraps `ContentUnavailableView` with
//  defaults that match the app's tone.
//

import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String?
    var action: (() -> Void)?
    var actionTitle: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message = message {
                Text(message)
            }
        } actions: {
            if let action = action, let actionTitle = actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    EmptyStateView(
        title: "暂无投资组合",
        systemImage: "tray",
        message: "点击右上角 + 创建你的第一个组合",
        action: {},
        actionTitle: "创建组合"
    )
}
