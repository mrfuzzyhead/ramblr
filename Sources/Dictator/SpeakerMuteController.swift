import CoreAudio
import Foundation

/// Mutes the default output device for the duration of a recording, then restores
/// the previous mute/volume state. Prefers the hardware mute switch; falls back to
/// volume = 0 when mute is not settable (some HDMI/USB devices).
@MainActor
final class SpeakerMuteController {
    private struct Restoration {
        let deviceID: AudioDeviceID
        let mutedChannels: [AudioObjectPropertyElement]
        let previousVolumes: [(element: AudioObjectPropertyElement, volume: Float32)]
    }

    private var restoration: Restoration?

    func mute() {
        guard restoration == nil else { return }
        guard let deviceID = Self.defaultOutputDeviceID() else { return }

        let muteChannels = Self.settableElements(
            deviceID: deviceID,
            selector: kAudioDevicePropertyMute
        )

        if !muteChannels.isEmpty {
            let alreadyMuted = muteChannels.allSatisfy {
                Self.muteValue(deviceID: deviceID, element: $0) == true
            }
            restoration = Restoration(deviceID: deviceID, mutedChannels: alreadyMuted ? [] : muteChannels, previousVolumes: [])
            guard !alreadyMuted else { return }
            for element in muteChannels {
                Self.setMuteValue(true, deviceID: deviceID, element: element)
            }
            return
        }

        let volumeChannels = Self.settableElements(
            deviceID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar
        )
        var previousVolumes: [(element: AudioObjectPropertyElement, volume: Float32)] = []
        for element in volumeChannels {
            guard let volume = Self.volumeValue(deviceID: deviceID, element: element), volume > 0 else { continue }
            previousVolumes.append((element, volume))
            Self.setVolumeValue(0, deviceID: deviceID, element: element)
        }
        restoration = Restoration(deviceID: deviceID, mutedChannels: [], previousVolumes: previousVolumes)
    }

    func restore() {
        guard let restoration else { return }
        self.restoration = nil

        for element in restoration.mutedChannels {
            Self.setMuteValue(false, deviceID: restoration.deviceID, element: element)
        }
        for entry in restoration.previousVolumes {
            Self.setVolumeValue(entry.volume, deviceID: restoration.deviceID, element: entry.element)
        }
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func settableElements(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectPropertyElement] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if isSettable(deviceID: deviceID, address: &address) {
            return [kAudioObjectPropertyElementMain]
        }

        var elements: [AudioObjectPropertyElement] = []
        let channelCount = max(outputChannelCount(for: deviceID), 2)
        for channel in 1...UInt32(channelCount) {
            address.mElement = channel
            if isSettable(deviceID: deviceID, address: &address) {
                elements.append(channel)
            }
        }
        return elements
    }

    private static func isSettable(deviceID: AudioDeviceID, address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    private static func muteValue(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    private static func setMuteValue(_ muted: Bool, deviceID: AudioDeviceID, element: AudioObjectPropertyElement) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var value: UInt32 = muted ? 1 : 0
        _ = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
    }

    private static func volumeValue(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func setVolumeValue(_ volume: Float32, deviceID: AudioDeviceID, element: AudioObjectPropertyElement) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var value = volume
        _ = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        )
    }

    private static func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else {
            return 0
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, raw) == noErr else {
            return 0
        }

        let bufferList = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
