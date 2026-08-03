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

        previousDefaultUID = MicrophoneDeviceManager.defaultInputDeviceUID()
        try MicrophoneDeviceManager.setDefaultInputDevice(uid: microphoneUID)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictator-\(UUID().uuidString).m4a")
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

        if let previous = previousDefaultUID {
            try? MicrophoneDeviceManager.setDefaultInputDevice(uid: previous)
        }
        previousDefaultUID = nil
        guard let url else { return nil }
        return (url, durationMs)
    }

    func cancel() {
        if let result = stop() {
            try? FileManager.default.removeItem(at: result.url)
        }
    }
}

