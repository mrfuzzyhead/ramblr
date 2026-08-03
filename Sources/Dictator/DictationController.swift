import AppKit
import Combine
import Foundation

enum DictationState: Equatable {
    case idle
    case recording
    case processing
}

@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    @Published private(set) var state: DictationState = .idle
    @Published var lastError: String?

    private let settings = SettingsStore.shared
    private let recorder = AudioRecorder()
    private let openAI = OpenAIService()
    private var hotKeyManager: HotKeyManager?
    private var recordingStartedAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private let minimumRecordingDuration: TimeInterval = 0.35

    private init() {}

    var isHotKeyTapActive: Bool {
        hotKeyManager?.isTapActive == true
    }

    func start() {
        installHotKeys()

        settings.$shortcut
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.hotKeyManager?.update(shortcut: shortcut)
            }
            .store(in: &cancellables)
    }

    func restartHotKeys() {
        installHotKeys()
    }

    private func installHotKeys() {
        hotKeyManager?.stop()
        let manager = HotKeyManager(shortcut: settings.shortcut)
        manager.onKeyDown = { [weak self] in
            self?.beginRecording()
        }
        manager.onKeyUp = { [weak self] in
            self?.endRecording()
        }
        manager.start()
        hotKeyManager = manager
    }

    func beginRecording() {
        guard state == .idle else { return }
        lastError = nil

        Task {
            if !MicrophoneDeviceManager.permissionGranted() {
                let granted = await MicrophoneDeviceManager.requestPermission()
                guard granted else {
                    lastError = MicrophoneError.permissionDenied.localizedDescription
                    ToastPresenter.shared.show(message: lastError ?? "Microphone permission denied.")
                    return
                }
            }

            do {
                try recorder.start(microphoneUID: settings.microphoneUID)
                recordingStartedAt = Date()
                state = .recording
            } catch {
                lastError = error.localizedDescription
                ToastPresenter.shared.show(message: error.localizedDescription)
            }
        }
    }

    func endRecording() {
        guard state == .recording else { return }

        let started = recordingStartedAt
        recordingStartedAt = nil
        guard let recording = recorder.stop() else {
            state = .idle
            return
        }
        let fileURL = recording.url
        let audioDurationMs = recording.durationMs

        if let started, Date().timeIntervalSince(started) < minimumRecordingDuration {
            try? FileManager.default.removeItem(at: fileURL)
            state = .idle
            return
        }

        state = .processing
        Task {
            defer {
                try? FileManager.default.removeItem(at: fileURL)
            }

            do {
                let apiKey = settings.apiKey
                let requestStarted = Date()
                let text = try await openAI.transcribe(fileURL: fileURL, apiKey: apiKey)
                let transcriptionMs = max(
                    0,
                    Int((Date().timeIntervalSince(requestStarted) * 1000).rounded())
                )

                let editable = FocusPasteService.hasEditableFocus()
                FocusPasteService.copyToClipboard(text)

                if editable {
                    FocusPasteService.paste(text)
                } else {
                    ToastPresenter.shared.show(
                        message: "No field in focus. Transcription copied to the clipboard."
                    )
                }

                settings.prependHistory(
                    TranscriptionEntry(
                        text: text,
                        pasted: editable,
                        audioDurationMs: audioDurationMs,
                        transcriptionMs: transcriptionMs
                    )
                )
                state = .idle
            } catch {
                lastError = error.localizedDescription
                ToastPresenter.shared.show(message: error.localizedDescription)
                state = .idle
            }
        }
    }
}
