import AppKit
import SwiftUI

@MainActor
final class ToastService {
    private var panel: NSPanel?
    private var currentAppearance: NSAppearance?
    private var hostingView: NSHostingView<ToastView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var presentationGeneration: Int = 0

    func setAppearance(_ appearance: NSAppearance?) {
        currentAppearance = appearance
        panel?.appearance = appearance
    }

    func show(message: String, isSuccess: Bool) {
        presentationGeneration += 1
        let generation = presentationGeneration

        let panel = panel ?? createPanel()
        panel.appearance = currentAppearance

        let rootView = ToastView(message: message, isSuccess: isSuccess)
        let host: NSHostingView<ToastView>
        if let existingHost = hostingView {
            existingHost.rootView = rootView
            host = existingHost
        } else {
            let newHostingView = NSHostingView(rootView: rootView)
            hostingView = newHostingView
            panel.contentView = newHostingView
            host = newHostingView
        }

        host.layoutSubtreeIfNeeded()
        let fittingSize = host.fittingSize
        let clampedSize = NSSize(
            width: min(max(ceil(fittingSize.width), 180), 360),
            height: max(ceil(fittingSize.height), 36)
        )
        panel.setContentSize(clampedSize)

        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let screen = targetScreen {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: round(frame.midX - clampedSize.width / 2),
                    y: round(frame.maxY - clampedSize.height - 56)
                )
            )
        }

        let needsFadeIn = !panel.isVisible || panel.alphaValue < 0.99
        if needsFadeIn {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        if needsFadeIn {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.presentationGeneration == generation, let panel = self.panel else {
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.presentationGeneration == generation else {
                        return
                    }
                    self.panel?.orderOut(nil)
                    self.panel?.alphaValue = 1
                }
            })
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.appearance = currentAppearance
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
                .font(.ui(.body, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Design.Space.xl)
        .padding(.vertical, Design.Space.md)
        .frame(minWidth: 180, maxWidth: 360, alignment: .leading)
        .materialSurface(
            material: .hudWindow,
            blendingMode: .behindWindow,
            state: .active,
            tint: Constants.VisualStyle.surfaceRaised.opacity(0.72),
            cornerRadius: Design.cardCornerRadius,
            borderColor: Constants.VisualStyle.borderStrong
        )
    }
}
