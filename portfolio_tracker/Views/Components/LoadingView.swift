//
//  LoadingView.swift
//  portfolio_tracker
//
//  Standardized inline / overlay loading indicator.
//

import SwiftUI

struct LoadingView: View {
    var message: String?
    var style: Style = .inline

    enum Style {
        /// Lightweight row — spinner + optional text.
        case inline
        /// Centered overlay suitable for blocking the content area.
        case overlay
    }

    var body: some View {
        switch style {
        case .inline:
            HStack(spacing: AppSpacing.m) {
                ProgressView()
                    .controlSize(.small)
                if let message = message {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message ?? "加载中")
        case .overlay:
            VStack(spacing: AppSpacing.l) {
                ProgressView()
                    .controlSize(.large)
                if let message = message {
                    Text(message)
                        .font(AppFont.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message ?? "加载中")
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        LoadingView(message: "正在加载价格…")
        LoadingView(message: "正在分析再平衡…", style: .overlay)
            .frame(height: 160)
    }
    .padding()
}
