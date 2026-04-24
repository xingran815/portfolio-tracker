//
//  ToastView.swift
//  portfolio_tracker
//
//  Transient status banner for success / error / info notifications. Pair with
//  the `.toast(_:)` view modifier for ephemeral presentation.
//

import SwiftUI

enum ToastKind {
    case success
    case error
    case info
    case warning

    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success: return AppColor.success
        case .error: return AppColor.danger
        case .info: return AppColor.info
        case .warning: return AppColor.warning
        }
    }
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    let kind: ToastKind
    let message: String

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: toast.kind.systemImage)
                .foregroundStyle(toast.kind.tint)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(AppFont.rowSubtitle)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.l)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .shadow(radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
    }
}

// MARK: - Presenter

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    var duration: TimeInterval = 2.5

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = toast {
                ToastView(toast: toast)
                    .padding(.top, AppSpacing.l)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                        withAnimation { self.toast = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
    }
}

extension View {
    /// Presents a transient toast anchored to the top of the view. Pass a
    /// binding; set it to non-nil to show, it auto-clears after `duration`.
    func toast(_ toast: Binding<Toast?>, duration: TimeInterval = 2.5) -> some View {
        modifier(ToastModifier(toast: toast, duration: duration))
    }
}

#Preview {
    VStack(spacing: 20) {
        ToastView(toast: Toast(kind: .success, message: "组合已保存"))
        ToastView(toast: Toast(kind: .error, message: "网络连接失败"))
        ToastView(toast: Toast(kind: .warning, message: "汇率数据过期"))
        ToastView(toast: Toast(kind: .info, message: "正在同步价格"))
    }
    .padding()
}
