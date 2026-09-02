import AppKit
import SwiftUI

@MainActor
final class ToastService {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(message: String, isSuccess: Bool) {
        let panel = panel ?? createPanel()
        panel.contentView = NSHostingView(rootView: ToastView(message: message, isSuccess: isSuccess))

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.maxX - size.width - 20,
                    y: frame.maxY - size.height - 20
                )
            )
        }

        panel.orderFrontRegardless()

        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

private struct ToastView: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.icon(.base, weight: .semibold))
                .foregroundStyle(isSuccess ? Constants.VisualStyle.success : Constants.VisualStyle.warn)

            Text(message)
                .font(.ui(.body))
                .foregroundStyle(Constants.VisualStyle.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                .strokeBorder(Constants.VisualStyle.borderStrong, lineWidth: Constants.Layout.hairline)
        )
    }
}
