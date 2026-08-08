import AVFoundation
import CoreAudio
import Foundation

struct MicrophoneDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let audioDeviceID: AudioDeviceID
}

enum MicrophoneDeviceManager {
    private static let cacheLock = NSLock()
    private static var deviceIDByUID: [String: AudioDeviceID] = [:]

    static func listInputDevices() -> [MicrophoneDevice] {
        let deviceIDs = allAudioDeviceIDs()
        var devices: [MicrophoneDevice] = []
        var cache: [String: AudioDeviceID] = [:]

        for deviceID in deviceIDs {
            guard inputChannelCount(for: deviceID) > 0 else { continue }
            let name = deviceName(for: deviceID) ?? "Microphone \(deviceID)"
            let uid = deviceUID(for: deviceID) ?? String(deviceID)
            cache[uid] = deviceID
            devices.append(MicrophoneDevice(id: uid, name: name, audioDeviceID: deviceID))
        }

        replaceCache(cache)
        return devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultInputDeviceUID() -> String? {
        guard let deviceID = defaultInputDeviceID() else { return nil }
        return deviceUID(for: deviceID)
    }

    /// Sets the system default input device when needed.
    /// - Returns: `true` when the system default was changed.
    /// - Note: `uid == nil` means “use system default” and is always a no-op.
    @discardableResult
    static func setDefaultInputDevice(uid: String?) throws -> Bool {
        guard let uid else { return false }

        if defaultInputDeviceUID() == uid {
            return false
        }

        let deviceID: AudioDeviceID
        if let resolved = audioDeviceID(forUID: uid) {
            deviceID = resolved
        } else if let fallback = firstInputDeviceID() {
            if deviceUID(for: fallback) == defaultInputDeviceUID() {
                return false
            }
            deviceID = fallback
        } else {
            throw MicrophoneError.noInputDevices
        }

        try applyDefaultInputDevice(deviceID)
        return true
    }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func permissionGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Resolves a device UID to an `AudioDeviceID`, using a cache when possible.
    static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        if let cached = cachedDeviceID(forUID: uid), isValidInputDevice(cached) {
            return cached
        }
        return refreshDeviceIDCache()[uid]
    }

    private static func applyDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &mutableDeviceID
        )
        guard status == noErr else {
            invalidateCache()
            throw MicrophoneError.failedToSetDevice(status)
        }
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != 0 else {
            return nil
        }
        return deviceID
    }

    private static func firstInputDeviceID() -> AudioDeviceID? {
        for deviceID in allAudioDeviceIDs() {
            guard inputChannelCount(for: deviceID) > 0 else { continue }
            if let uid = deviceUID(for: deviceID) {
                remember(uid: uid, deviceID: deviceID)
            }
            return deviceID
        }
        return nil
    }

    private static func allAudioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }
        return deviceIDs
    }

    private static func refreshDeviceIDCache() -> [String: AudioDeviceID] {
        var cache: [String: AudioDeviceID] = [:]
        for deviceID in allAudioDeviceIDs() {
            guard inputChannelCount(for: deviceID) > 0 else { continue }
            guard let uid = deviceUID(for: deviceID) else { continue }
            cache[uid] = deviceID
        }
        replaceCache(cache)
        return cache
    }

    private static func isValidInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        inputChannelCount(for: deviceID) > 0
    }

    private static func cachedDeviceID(forUID uid: String) -> AudioDeviceID? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return deviceIDByUID[uid]
    }

    private static func replaceCache(_ cache: [String: AudioDeviceID]) {
        cacheLock.lock()
        deviceIDByUID = cache
        cacheLock.unlock()
    }

    private static func invalidateCache() {
        cacheLock.lock()
        deviceIDByUID = [:]
        cacheLock.unlock()
    }

    private static func remember(uid: String, deviceID: AudioDeviceID) {
        cacheLock.lock()
        deviceIDByUID[uid] = deviceID
        cacheLock.unlock()
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else {
            return 0
        }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, raw) == noErr else {
            return 0
        }

        let bufferList = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return uid as String
    }
}

enum MicrophoneError: LocalizedError {
    case noInputDevices
    case failedToSetDevice(OSStatus)
    case permissionDenied
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevices:
            return "No microphones were found."
        case .failedToSetDevice(let status):
            return "Could not select microphone (error \(status))."
        case .permissionDenied:
            return "Microphone access is denied. Enable it in System Settings → Privacy & Security → Microphone."
        case .recordingFailed(let detail):
            return detail
        }
    }
}
