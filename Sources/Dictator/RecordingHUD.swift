import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingHUDPresenter {
    static let shared = RecordingHUDPresenter()

    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var isObserving = false

    private init() {}

    func start() {
        guard !isObserving else { return }
        isObserving = true

        DictationController.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.update(for: state)
            }
            .store(in: &cancellables)
    }

    private func update(for state: DictationState) {
        switch state {
        case .idle:
            hide()
        case .recording, .processing:
            show(state: state)
        }
    }

    private func show(state: DictationState) {
        let root = RecordingHUDView(state: state)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 52)

        if let panel {
            panel.contentView = hosting
            panel.setContentSize(hosting.frame.size)
            position(panel, size: hosting.frame.size)
            panel.orderFrontRegardless()
            return
        }

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

        position(panel, size: hosting.frame.size)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hide() {
        panel?.close()
        panel = nil
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.minY + 28
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct RecordingHUDView: View {
    let state: DictationState

    var body: some View {
        HStack(spacing: 10) {
            indicator
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(4)
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .idle:
            EmptyView()
        case .recording:
            RecordingPulseDot()
        case .processing:
            ProgressView()
                .controlSize(.small)
        }
    }

    private var label: String {
        switch state {
        case .idle:
            return ""
        case .recording:
            return "Recording"
        case .processing:
            return "Processing…"
        }
    }
}

private struct RecordingPulseDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .opacity(pulsing ? 0.45 : 1)
            .scaleEffect(pulsing ? 0.85 : 1)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear {
                pulsing = true
            }
    }
}
