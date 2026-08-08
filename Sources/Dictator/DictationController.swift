import AppKit
import Combine
import Foundation

enum DictationState: Equatable {
    case idle
    case preparing
    case recording
    case processing
    case complete
}

enum CaptureMode: Equatable {
    case dictation
    case compose
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
    private let openAI = OpenAIService()
    private var hotKeyManager: HotKeyManager?
    private var recordingStartedAt: Date?
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
            .combineLatest(settings.$composeShortcut)
            .dropFirst()
            .sink { [weak self] dictation, compose in
                self?.hotKeyManager?.update(dictation: dictation, compose: compose)
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
            compose: settings.composeShortcut
        )
        manager.onBegin = { [weak self] action in
            self?.beginRecording(mode: action == .compose ? .compose : .dictation)
        }
        manager.onSwitch = { [weak self] action in
            self?.mode = action == .compose ? .compose : .dictation
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

        guard state == .idle || state == .complete else { return }

        self.mode = mode
        lastError = nil
        recordingElapsed = 0
        state = .preparing

        Task {
            if !MicrophoneDeviceManager.permissionGranted() {
                let granted = await MicrophoneDeviceManager.requestPermission()
                guard granted else {
                    lastError = MicrophoneError.permissionDenied.localizedDescription
                    ToastPresenter.shared.show(message: lastError ?? "Microphone permission denied.")
                    state = .idle
                    return
                }
            }

            // Bail if the user already released during preparing.
            guard state == .preparing else { return }

            do {
                try recorder.start(microphoneUID: settings.microphoneUID)
                recordingStartedAt = Date()
                state = .recording
                startElapsedTimer()
            } catch {
                lastError = error.localizedDescription
                ToastPresenter.shared.show(message: error.localizedDescription)
                state = .idle
            }
        }
    }

    func endRecording() {
        guard state == .preparing || state == .recording else { return }

        stopElapsedTimer()

        if state == .preparing {
            recorder.cancel()
            recordingStartedAt = nil
            state = .idle
            return
        }

        let started = recordingStartedAt
        let captureMode = mode
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
                var text = try await openAI.transcribe(fileURL: fileURL, apiKey: apiKey)
                if captureMode == .compose {
                    text = try await openAI.composeEmail(from: text, apiKey: apiKey)
                }
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
                        kind: captureMode == .compose ? .compose : .dictation,
                        audioDurationMs: audioDurationMs,
                        transcriptionMs: transcriptionMs
                    )
                )
                showCompleteThenIdle()
            } catch {
                lastError = error.localizedDescription
                ToastPresenter.shared.show(message: error.localizedDescription)
                state = .idle
            }
        }
    }

    private func showCompleteThenIdle() {
        state = .complete
        completeResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.state == .complete {
                self.state = .idle
            }
        }
        completeResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
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
