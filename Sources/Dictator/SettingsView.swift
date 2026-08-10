import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case microphone
    case artificialIntelligence
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .microphone: return "Microphone"
        case .artificialIntelligence: return "Artificial Intelligence"
        case .permissions: return "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .microphone: return "mic"
        case .artificialIntelligence: return "sparkle"
        case .permissions: return "lock.shield"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var dictation: DictationController

    @State private var pane: SettingsPane = .general
    @State private var microphones: [MicrophoneDevice] = []
    @State private var draftAPIKey = ""
    @State private var isEditingAPIKey = false
    @StateObject private var levelMonitor = MicrophoneLevelMonitor()

    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var micPermissionGranted = MicrophoneDeviceManager.permissionGranted()
    @State private var accessibilityTrusted = FocusPasteService.isAccessibilityTrusted(prompt: false)
    @State private var inputMonitoringGranted = HotKeyManager.hasInputMonitoringAccess()
    @State private var hotkeyTapActive = DictationController.shared.isHotKeyTapActive

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().background(RamblrTheme.border)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(RamblrTheme.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 720, minHeight: 420)
        .ignoresSafeArea(edges: .top)
        .onAppear {
            refreshDevices()
            refreshPermissions()
            refreshLaunchAtLogin()
            isEditingAPIKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .onChange(of: pane) { _, newValue in
            if newValue == .microphone {
                levelMonitor.start(deviceUID: settings.microphoneUID)
            } else {
                levelMonitor.stop()
            }
        }
        .onChange(of: settings.microphoneUID) { _, uid in
            if pane == .microphone {
                levelMonitor.start(deviceUID: uid)
            }
        }
        .onDisappear {
            levelMonitor.stop()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissions()
            refreshLaunchAtLogin()
            if pane == .microphone {
                refreshDevices()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsPane.allCases) { item in
                Button {
                    pane = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        pane == item ? RamblrTheme.selection : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 38)
        .padding(.bottom, 12)
        .frame(width: 220)
        .background(RamblrTheme.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .general:
            generalPane
        case .shortcuts:
            shortcutsPane
        case .microphone:
            microphonePane
        case .artificialIntelligence:
            aiPane
        case .permissions:
            permissionsPane
        }
    }

    private var generalPane: some View {
        settingsDetail(
            title: "General",
            subtitle: "App behaviour and startup options."
        ) {
            settingsCard {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start at Login")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(launchAtLoginSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(RamblrTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Toggle("Start at Login", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(RamblrTheme.accent)
                }
                .padding(16)
            }

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            if LaunchAtLogin.status == .requiresApproval {
                Button("Open Login Items Settings") {
                    LaunchAtLogin.openLoginItemsSettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(RamblrTheme.accent)
                .font(.system(size: 12, weight: .medium))
            }
        }
    }

    private var shortcutsPane: some View {
        settingsDetail(
            title: "Shortcuts",
            subtitle: "Select the keyboard bindings to start recording."
        ) {
            settingsCard {
                shortcutRow(
                    title: "Dictation Hotkey",
                    subtitle: "Press and hold to speak, let go to paste",
                    shortcut: $settings.shortcut
                )
                Divider().background(RamblrTheme.border)
                shortcutRow(
                    title: "Dictate and Send Hotkey",
                    subtitle: "Hold to speak, release to paste and send",
                    shortcut: $settings.dictateAndSendShortcut
                )
            }
        }
    }

    private var microphonePane: some View {
        settingsDetail(
            title: "Microphone",
            subtitle: "Select the default microphone to use for recording audio."
        ) {
            settingsCard {
                microphoneRow(
                    title: autoDetectTitle,
                    subtitle: "Use system default microphone",
                    selected: settings.microphoneUID == nil,
                    showMeter: settings.microphoneUID == nil
                ) {
                    settings.microphoneUID = nil
                }

                ForEach(microphones) { device in
                    Divider().background(RamblrTheme.border)
                    microphoneRow(
                        title: device.name,
                        subtitle: microphoneSubtitle(for: device.name),
                        selected: settings.microphoneUID == device.id,
                        showMeter: settings.microphoneUID == device.id
                    ) {
                        settings.microphoneUID = device.id
                    }
                }
            }
        }
    }

    private var aiPane: some View {
        settingsDetail(
            title: "Artificial Intelligence",
            subtitle: "Enter your OpenAI key for transcribing."
        ) {
            if isEditingAPIKey || settings.apiKey.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField("sk-…", text: $draftAPIKey)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(RamblrTheme.border, lineWidth: 1)
                        )
                        .foregroundStyle(.white)

                    Button("Save") {
                        settings.apiKey = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        draftAPIKey = ""
                        isEditingAPIKey = settings.apiKey.isEmpty
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RamblrTheme.accent)
                    .foregroundStyle(.black)
                    .disabled(draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack {
                    Text(maskedAPIKey)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        draftAPIKey = ""
                        isEditingAPIKey = true
                    } label: {
                        Text("Change")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RamblrTheme.elevated,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(RamblrTheme.border, lineWidth: 1)
                )

                Text("Your key is stored securely in the key vault and is not visible in Ramblr. Click the change button to use a different key.")
                    .font(.system(size: 12))
                    .foregroundStyle(RamblrTheme.secondaryText)
            }

            if let error = dictation.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var permissionsPane: some View {
        settingsDetail(
            title: "Permissions",
            subtitle: "Ramblr needs these permissions for global shortcuts and pasting."
        ) {
            settingsCard {
                permissionRow(
                    title: "Microphone",
                    granted: micPermissionGranted,
                    actionTitle: micPermissionGranted ? "Granted" : "Request access"
                ) {
                    Task {
                        micPermissionGranted = await MicrophoneDeviceManager.requestPermission()
                    }
                }
                Divider().background(RamblrTheme.border)
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
                Divider().background(RamblrTheme.border)
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
            }

            Text("Input Monitoring is required for shortcuts when Ramblr is in the background. Accessibility is required to detect the focused field and paste.")
                .font(.system(size: 12))
                .foregroundStyle(RamblrTheme.secondaryText)
        }
    }

    private func settingsDetail<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(RamblrTheme.secondaryText)
                }
                content()
            }
            .padding(.horizontal, 28)
            .padding(.top, 38)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(RamblrTheme.border, lineWidth: 1)
        )
    }

    private func shortcutRow(
        title: String,
        subtitle: String,
        shortcut: Binding<KeyboardShortcut>
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(RamblrTheme.secondaryText)
            }
            Spacer()
            ShortcutRecorderView(shortcut: shortcut)
        }
        .padding(16)
    }

    private func microphoneRow(
        title: String,
        subtitle: String,
        selected: Bool,
        showMeter: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? RamblrTheme.accent : RamblrTheme.tertiaryText)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(RamblrTheme.secondaryText)
                }
                Spacer()
                if showMeter {
                    LevelMeterView(level: levelMonitor.level)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(granted ? RamblrTheme.levelActive : .orange)
                Text(title)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(actionTitle)
                    .foregroundStyle(granted ? RamblrTheme.tertiaryText : RamblrTheme.accent)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(granted)
    }

    private func microphoneSubtitle(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("macbook") || lowered.contains("built-in") || lowered.contains("imac") {
            return "Built-in microphone"
        }
        return "External microphone"
    }

    private var autoDetectTitle: String {
        if let uid = MicrophoneDeviceManager.defaultInputDeviceUID(),
           let device = microphones.first(where: { $0.id == uid }) {
            return "Auto-detect (\(device.name))"
        }
        return "Auto-detect (System Default)"
    }

    private var maskedAPIKey: String {
        let key = settings.apiKey
        guard key.count > 10 else { return String(repeating: "•", count: max(key.count, 8)) }
        let prefix = String(key.prefix(3))
        let suffix = String(key.suffix(8))
        return "\(prefix).......\(suffix)"
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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { enabled in
                do {
                    let status = try LaunchAtLogin.setEnabled(enabled)
                    launchAtLoginEnabled = status == .enabled
                    if status == .requiresApproval {
                        launchAtLoginError = "macOS needs approval before Ramblr can start at login."
                        LaunchAtLogin.openLoginItemsSettings()
                    } else {
                        launchAtLoginError = nil
                    }
                } catch {
                    launchAtLoginEnabled = LaunchAtLogin.isEnabled
                    launchAtLoginError = error.localizedDescription
                }
            }
        )
    }

    private var launchAtLoginSubtitle: String {
        switch LaunchAtLogin.status {
        case .requiresApproval:
            return "Waiting for approval in System Settings → General → Login Items"
        case .notFound:
            return "Available when Ramblr is installed as an app (not from swift run)"
        default:
            return "Launch Ramblr automatically when you log in"
        }
    }

    private func refreshLaunchAtLogin() {
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
        if LaunchAtLogin.isEnabled {
            launchAtLoginError = nil
        }
    }
}

private struct LevelMeterView: View {
    let level: Float
    private let barCount = 8

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index < activeBars ? RamblrTheme.levelActive : RamblrTheme.levelInactive)
                    .frame(width: 4, height: 14)
            }
        }
    }

    private var activeBars: Int {
        Int((level * Float(barCount)).rounded())
    }
}
