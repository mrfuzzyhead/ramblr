import AppKit
import SwiftUI

@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(message: String, duration: TimeInterval = 3.5) {
        hideWorkItem?.cancel()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil

        let root = ToastView(message: message)
            .preferredColorScheme(.dark)
        let hosting = NSHostingView(rootView: root)
        let fitting = hosting.fittingSize
        let size = NSSize(
            width: max(220, min(420, fitting.width)),
            height: max(52, fitting.height)
        )
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hosting
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.setContentSize(size)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.midX - size.width / 2
            let y = visible.minY + 28
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.close()
            self?.panel = nil
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 8, height: 8)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RamblrTheme.hudBackground, in: Capsule())
        .fixedSize()
        .padding(4)
    }
}
