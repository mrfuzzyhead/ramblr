import AVFoundation
import Combine
import Foundation

@MainActor
final class MicrophoneLevelMonitor: ObservableObject {
    @Published private(set) var level: Float = 0

    private var engine: AVAudioEngine?
    private var isRunning = false

    func start(deviceUID: String?) {
        stop()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            return
        }

        if let deviceUID {
            _ = try? MicrophoneDeviceManager.setDefaultInputDevice(uid: deviceUID)
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let magnitude = Self.rms(buffer: buffer)
            Task { @MainActor in
                self?.level = magnitude
            }
        }

        do {
            try engine.start()
            self.engine = engine
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            self.engine = nil
            isRunning = false
        }
    }

    func stop() {
        guard isRunning || engine != nil else {
            level = 0
            return
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        level = 0
    }

    private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        let mean = sum / Float(frameCount)
        let rms = sqrt(mean)
        // Map roughly into 0...1 for UI bars.
        return min(1, max(0, rms * 8))
    }
}
