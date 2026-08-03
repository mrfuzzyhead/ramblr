import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            Text(isRecording ? "Press shortcut…" : shortcut.displayString)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                )

            Button(isRecording ? "Cancel" : "Change") {
                isRecording.toggle()
            }
        }
        .background(
            ShortcutCaptureRepresentable(isRecording: $isRecording) { event in
                let next = KeyboardShortcut(event: event)
                guard !next.modifierFlags.isEmpty else { return }
                shortcut = next
                isRecording = false
            }
        )
    }
}

private struct ShortcutCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (NSEvent) -> Void

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
        }
    }
}

final class ShortcutCaptureView: NSView {
    var isRecording = false
    var onCapture: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(53) { // Escape
            return
        }
        onCapture?(event)
    }
}
