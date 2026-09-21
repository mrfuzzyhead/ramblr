import AppKit
import Combine
import Foundation

enum DictationState: Equatable {
    case idle
    case preparing
    case recording
    case processing
    case complete
    case notice(String)
}

enum CaptureMode: Equatable {
    case dictation
    case dictateAndSend
}

@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var mode: CaptureMode = .dictation
    @Published private(set) var recordingElapsed: TimeInterval = 0
    @Published var lastError: String?

    private let settings = SettingsStore.shared
    private let recorder = AudioRecorder()
    private let speakerMute = SpeakerMuteController()
    private let openAI = OpenAIService()
    private let gemini = GeminiService()
    private var hotKeyManager: HotKeyManager?
    private var recordingStartedAt: Date?
    private var clipboardSnapshot: ClipboardSnapshot?
    private var elapsedTimer: Timer?
    private var completeResetWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private let minimumRecordingDuration: TimeInterval = 0.35

    private init() {}

    var isHotKeyTapActive: Bool {
        hotKeyManager?.isTapActive == true
    }

    func start() {
        installHotKeys()

        settings.$shortcut
            .combineLatest(settings.$dictateAndSendShortcut)
            .dropFirst()
            .sink { [weak self] dictation, dictateAndSend in
                self?.hotKeyManager?.update(dictation: dictation, dictateAndSend: dictateAndSend)
            }
            .store(in: &cancellables)
    }

    func restartHotKeys() {
        installHotKeys()
    }

    private func installHotKeys() {
        hotKeyManager?.stop()
        let manager = HotKeyManager(
            dictation: settings.shortcut,
            dictateAndSend: settings.dictateAndSendShortcut
        )
        manager.onBegin = { [weak self] action in
            self?.beginRecording(mode: action == .dictateAndSend ? .dictateAndSend : .dictation)
        }
        manager.onSwitch = { [weak self] action in
            self?.mode = action == .dictateAndSend ? .dictateAndSend : .dictation
        }
        manager.onEnd = { [weak self] _ in
            self?.endRecording()
        }
        manager.start()
        hotKeyManager = manager
    }

    func beginRecording(mode: CaptureMode) {
        completeResetWorkItem?.cancel()
        completeResetWorkItem = nil

        if state == .preparing || state == .recording {
            self.mode = mode
            return
        }

        switch state {
        case .idle, .complete, .notice:
            break
        default:
            return
        }

        self.mode = mode
        lastError = nil
        recordingElapsed = 0
        state = .preparing
        muteSpeakersIfNeeded()

        if MicrophoneDeviceManager.permissionGranted() {
            finishBeginRecording()
            return
        }

        Task {
            let granted = await MicrophoneDeviceManager.requestPermission()
            guard granted else {
                restoreSpeakers()
                lastError = MicrophoneError.permissionDenied.localizedDescription
                ToastPresenter.shared.show(message: lastError ?? "Microphone permission denied.")
                state = .idle
                return
            }

            // Bail if the user already released during preparing.
            guard state == .preparing else { return }
            finishBeginRecording()
        }
    }

    private func finishBeginRecording() {
        guard state == .preparing else { return }

        do {
            try recorder.start(microphoneUID: settings.microphoneUID)
            // Capture before we later overwrite the pasteboard for ⌘V.
            clipboardSnapshot = FocusPasteService.captureClipboard()
            recordingStartedAt = Date()
            state = .recording
            startElapsedTimer()
        } catch {
            restoreSpeakers()
            lastError = error.localizedDescription
            ToastPresenter.shared.show(message: error.localizedDescription)
            clipboardSnapshot = nil
            state = .idle
        }
    }

    func endRecording() {
        guard state == .preparing || state == .recording else { return }

        restoreSpeakers()
        stopElapsedTimer()

        if state == .preparing {
            recorder.cancel()
            recordingStartedAt = nil
            clipboardSnapshot = nil
            state = .idle
            return
        }

        let started = recordingStartedAt
        let captureMode = mode
        let priorClipboard = clipboardSnapshot
        recordingStartedAt = nil
        clipboardSnapshot = nil
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
                let provider = settings.transcriptionProvider
                let requestStarted = Date()
                let text: String
                switch provider {
                case .openAI:
                    text = try await openAI.transcribe(fileURL: fileURL, apiKey: settings.apiKey)
                case .gemini:
                    text = try await gemini.transcribe(fileURL: fileURL, apiKey: settings.geminiAPIKey)
                }
                let transcriptionMs = max(
                    0,
                    Int((Date().timeIntervalSince(requestStarted) * 1000).rounded())
                )

                let editable = FocusPasteService.hasEditableFocus()

                if editable {
                    if captureMode == .dictateAndSend {
                        FocusPasteService.pasteAndSend(text, restoringClipboard: priorClipboard)
                    } else {
                        FocusPasteService.paste(text, restoringClipboard: priorClipboard)
                    }
                } else {
                    // Leave the transcript on the clipboard for manual paste.
                    FocusPasteService.copyToClipboard(text)
                }

                settings.prependHistory(
                    TranscriptionEntry(
                        text: text,
                        pasted: editable,
                        kind: captureMode == .dictateAndSend ? .dictateAndSend : .dictation,
                        audioDurationMs: audioDurationMs,
                        transcriptionMs: transcriptionMs
                    )
                )

                if editable {
                    showTransientThenIdle(.complete)
                } else {
                    showTransientThenIdle(.notice("No field in focus"))
                }
            } catch {
                lastError = error.localizedDescription
                showTransientThenIdle(.notice(error.localizedDescription))
            }
        }
    }

    private func showTransientThenIdle(_ next: DictationState) {
        state = next
        completeResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            switch self.state {
            case .complete, .notice:
                self.state = .idle
            default:
                break
            }
        }
        completeResetWorkItem = work
        let delay: TimeInterval
        switch next {
        case .complete:
            delay = 1.25
        default:
            delay = 3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func prepareForTermination() {
        restoreSpeakers()
    }

    private func muteSpeakersIfNeeded() {
        guard settings.muteSpeakersWhileRecording else { return }
        speakerMute.mute()
    }

    private func restoreSpeakers() {
        speakerMute.restore()
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        recordingElapsed = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.state == .recording, let started = self.recordingStartedAt else { return }
                self.recordingElapsed = Date().timeIntervalSince(started)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
