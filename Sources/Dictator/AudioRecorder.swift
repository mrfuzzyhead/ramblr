import AVFoundation
import Foundation

@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var previousDefaultUID: String?

    var isRecording: Bool { recorder?.isRecording == true }

    func start(microphoneUID: String?) throws {
        guard !isRecording else { return }

        if !MicrophoneDeviceManager.permissionGranted() {
            throw MicrophoneError.permissionDenied
        }

        previousDefaultUID = nil
        if let microphoneUID {
            let currentUID = MicrophoneDeviceManager.defaultInputDeviceUID()
            if microphoneUID != currentUID {
                previousDefaultUID = currentUID
                try MicrophoneDeviceManager.setDefaultInputDevice(uid: microphoneUID)
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ramblr-\(UUID().uuidString).m4a")
        outputURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = false
        guard recorder.record() else {
            restorePreviousDefaultInputIfNeeded()
            throw MicrophoneError.recordingFailed("Could not start audio recording.")
        }
        self.recorder = recorder
    }

    /// Stops recording and returns the file URL plus clip duration in milliseconds.
    func stop() -> (url: URL, durationMs: Int)? {
        guard let recorder else { return nil }
        let durationMs = max(0, Int((recorder.currentTime * 1000).rounded()))
        recorder.stop()
        self.recorder = nil
        let url = outputURL
        outputURL = nil

        restorePreviousDefaultInputIfNeeded()
        guard let url else { return nil }
        return (url, durationMs)
    }

    func cancel() {
        if let result = stop() {
            try? FileManager.default.removeItem(at: result.url)
        }
    }

    private func restorePreviousDefaultInputIfNeeded() {
        guard let previous = previousDefaultUID else { return }
        previousDefaultUID = nil
        _ = try? MicrophoneDeviceManager.setDefaultInputDevice(uid: previous)
    }
}
