import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingHUDPresenter {
    static let shared = RecordingHUDPresenter()

    private let model = RecordingHUDModel()
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var isObserving = false

    private static let hudSize = NSSize(width: 228, height: 52)

    private init() {}

    func start() {
        guard !isObserving else { return }
        isObserving = true

        let dictation = DictationController.shared
        dictation.$state
            .combineLatest(dictation.$recordingElapsed)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, elapsed in
                self?.update(state: state, elapsed: elapsed)
            }
            .store(in: &cancellables)
    }

    private func update(state: DictationState, elapsed: TimeInterval) {
        switch state {
        case .idle:
            hide()
        case .preparing, .recording, .processing, .complete, .notice:
            model.state = state
            model.elapsed = elapsed
            show()
        }
    }

    private func show() {
        if panel == nil {
            let root = RecordingHUDRoot(model: model)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(origin: .zero, size: Self.hudSize)

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
            panel.setContentSize(Self.hudSize)
            position(panel)
            self.panel = panel
        }

        panel?.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = Self.hudSize
        let x = visible.midX - size.width / 2
        let y = visible.minY + 28
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

private struct RecordingHUDRoot: View {
    @ObservedObject var model: RecordingHUDModel

    var body: some View {
        RecordingHUDView(model: model)
            .preferredColorScheme(.dark)
    }
}

@MainActor
private final class RecordingHUDModel: ObservableObject {
    @Published var state: DictationState = .idle
    @Published var elapsed: TimeInterval = 0
}

private struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel

    var body: some View {
        Group {
            if case .notice(let message) = model.state {
                noticeContent(message)
            } else {
                statusContent
            }
        }
        .padding(4)
    }

    private var statusContent: some View {
        HStack(spacing: 10) {
            indicator
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(timeLabel)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(RamblrTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 220, height: 44)
        .background(RamblrTheme.hudBackground, in: Capsule())
        .frame(width: 220, height: 44)
    }

    private func noticeContent(_ message: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 8, height: 8)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 220, height: 44)
        .background(RamblrTheme.hudBackground, in: Capsule())
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.state {
        case .idle, .notice:
            EmptyView()
        case .preparing:
            Circle()
                .fill(Color.white.opacity(0.25))
        case .recording:
            Circle()
                .fill(RamblrTheme.recordingDot)
        case .processing:
            ProgressView()
                .controlSize(.mini)
                .colorScheme(.dark)
                .scaleEffect(0.55)
        case .complete:
            Circle()
                .fill(RamblrTheme.completeDot)
        }
    }

    private var label: String {
        switch model.state {
        case .idle, .notice:
            return ""
        case .preparing:
            return "Preparing"
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .complete:
            return "Complete"
        }
    }

    private var timeLabel: String {
        switch model.state {
        case .preparing, .idle, .notice:
            return "--:--"
        case .recording, .processing, .complete:
            let total = max(0, Int(model.elapsed.rounded()))
            let minutes = total / 60
            let seconds = total % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
