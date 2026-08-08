import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            HStack(spacing: 6) {
                if isRecording {
                    Text("Press shortcut…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RamblrTheme.secondaryText)
                } else if shortcut.keycapLabels.isEmpty {
                    Text("Click to record")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RamblrTheme.secondaryText)
                } else {
                    ForEach(Array(shortcut.keycapLabels.enumerated()), id: \.offset) { _, label in
                        KeycapView(label: label)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RamblrTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isRecording ? RamblrTheme.accent : RamblrTheme.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .background(
            ShortcutCaptureRepresentable(isRecording: $isRecording) { next in
                guard !next.modifierFlags.isEmpty || next.keyCode != nil else { return }
                shortcut = next
                isRecording = false
            }
        )
    }
}

struct KeycapView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct ShortcutCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (KeyboardShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
        nsView.onCapture = onCapture
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else {
            nsView.resetPeakFlags()
        }
    }
}

final class ShortcutCaptureView: NSView {
    var isRecording = false {
        didSet {
            if !isRecording {
                peakFlags = []
            }
        }
    }

    var onCapture: ((KeyboardShortcut) -> Void)?
    private var peakFlags: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }

    func resetPeakFlags() {
        peakFlags = []
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(53) { // Escape cancels
            return
        }
        if KeyboardShortcut.isModifierKeyCode(event.keyCode) {
            return
        }
        onCapture?(KeyboardShortcut(event: event))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        let flags = KeyboardShortcut.normalizeFlags(event.modifierFlags)
        if !flags.isEmpty {
            peakFlags = peakFlags.union(flags)
            return
        }

        guard !peakFlags.isEmpty else { return }
        let captured = peakFlags
        peakFlags = []
        onCapture?(KeyboardShortcut(keyCode: nil, modifiers: captured.rawValue))
    }
}
