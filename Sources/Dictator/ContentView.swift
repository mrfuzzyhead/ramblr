import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var dictation: DictationController

    @State private var microphones: [MicrophoneDevice] = []
    @State private var micPermissionGranted = MicrophoneDeviceManager.permissionGranted()
    @State private var accessibilityTrusted = FocusPasteService.isAccessibilityTrusted(prompt: false)
    @State private var inputMonitoringGranted = HotKeyManager.hasInputMonitoringAccess()
    @State private var hotkeyTapActive = DictationController.shared.isHotKeyTapActive

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    microphoneSection
                    historySection
                    permissionsSection
                    apiKeySection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 440, minHeight: 520)
        .onAppear {
            refreshDevices()
            refreshPermissions()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissions()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dictator")
                    .font(.title2.weight(.semibold))
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
        .padding(20)
    }

    private var statusLine: String {
        switch dictation.state {
        case .idle:
            return "Hold \(settings.shortcut.displayString) anywhere to dictate"
        case .recording:
            return "Recording… release to transcribe"
        case .processing:
            return "Transcribing and cleaning up…"
        }
    }

    private var statusBadge: some View {
        Group {
            switch dictation.state {
            case .idle:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .recording:
                Label("Recording", systemImage: "mic.fill")
                    .foregroundStyle(.red)
            case .processing:
                Label("Working", systemImage: "ellipsis.circle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout.weight(.medium))
    }

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Microphone")
                .font(.headline)

            Picker("Microphone", selection: microphoneSelection) {
                Text("System default").tag(Optional<String>.none)
                ForEach(microphones) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Button("Refresh microphones") {
                refreshDevices()
            }
            .buttonStyle(.link)

            VStack(alignment: .leading, spacing: 6) {
                Text("Global shortcut")
                    .font(.subheadline.weight(.medium))
                ShortcutRecorderView(shortcut: $settings.shortcut)
                Text("Hold the shortcut to record; release to transcribe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = dictation.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var microphoneSelection: Binding<String?> {
        Binding(
            get: { settings.microphoneUID },
            set: { settings.microphoneUID = $0 }
        )
    }

    private var permissionsSection: some View {
        settingsPanel(title: "Permissions") {
            VStack(alignment: .leading, spacing: 10) {
                permissionRow(
                    title: "Microphone",
                    granted: micPermissionGranted,
                    actionTitle: micPermissionGranted ? "Granted" : "Request access"
                ) {
                    Task {
                        micPermissionGranted = await MicrophoneDeviceManager.requestPermission()
                    }
                }

                permissionRow(
                    title: "Input Monitoring",
                    granted: inputMonitoringGranted && hotkeyTapActive,
                    actionTitle: inputMonitoringGranted ? (hotkeyTapActive ? "Granted" : "Retry") : "Grant access"
                ) {
                    _ = HotKeyManager.requestInputMonitoringAccess()
                    FocusPasteService.openInputMonitoringSettings()
                    dictation.restartHotKeys()
                    refreshPermissions()
                }

                permissionRow(
                    title: "Accessibility",
                    granted: accessibilityTrusted,
                    actionTitle: accessibilityTrusted ? "Granted" : "Grant access"
                ) {
                    accessibilityTrusted = FocusPasteService.isAccessibilityTrusted(prompt: true)
                    if !accessibilityTrusted {
                        FocusPasteService.openAccessibilitySettings()
                    }
                    _ = FocusPasteService.requestPostEventAccess()
                    refreshPermissions()
                }

                Text("Input Monitoring is required for the shortcut when Dictator is in the background. Accessibility is required to detect the focused field and paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var apiKeySection: some View {
        settingsPanel(title: "API key") {
            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI API key")
                    .font(.subheadline.weight(.medium))
                SecureField("sk-…", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func settingsPanel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            Button(actionTitle, action: action)
                .disabled(granted)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent transcriptions")
                    .font(.headline)
                Spacer()
                if !settings.history.isEmpty {
                    Button("Clear") {
                        settings.clearHistory()
                    }
                    .buttonStyle(.link)
                }
            }

            if settings.history.isEmpty {
                Text("Your recent dictations will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(settings.history) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: TranscriptionEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let timing = historyTimingLabel(for: entry) {
                    Text(timing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(entry.pasted ? "Pasted" : "Clipboard")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Spacer()
                Button("Copy") {
                    FocusPasteService.copyToClipboard(entry.text)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func historyTimingLabel(for entry: TranscriptionEntry) -> String? {
        switch (entry.audioDurationMs, entry.transcriptionMs) {
        case let (audio?, transcription?):
            return "\(audio) ms audio · \(transcription) ms response"
        case let (audio?, nil):
            return "\(audio) ms audio"
        case let (nil, transcription?):
            return "\(transcription) ms response"
        case (nil, nil):
            return nil
        }
    }

    private func refreshDevices() {
        microphones = MicrophoneDeviceManager.listInputDevices()
        if let uid = settings.microphoneUID,
           !microphones.contains(where: { $0.id == uid }) {
            settings.microphoneUID = nil
        }
    }

    private func refreshPermissions() {
        micPermissionGranted = MicrophoneDeviceManager.permissionGranted()
        accessibilityTrusted = FocusPasteService.isAccessibilityTrusted(prompt: false)
        inputMonitoringGranted = HotKeyManager.hasInputMonitoringAccess()
        hotkeyTapActive = dictation.isHotKeyTapActive
    }
}
