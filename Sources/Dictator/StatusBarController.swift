import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var mainWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()
    private let dictation = DictationController.shared
    private let settings = SettingsStore.shared

    override init() {
        super.init()
        configureStatusItem()
        rebuildMenu()
        observeState()
        RecordingHUDPresenter.shared.start()
        // Request quietly — do not show system permission sheets on every launch.
        // Settings → Permissions is the place to grant / re-grant after rebuilds.
        _ = HotKeyManager.requestInputMonitoringAccess()
        _ = FocusPasteService.requestPostEventAccess()
        _ = FocusPasteService.isAccessibilityTrusted(prompt: false)
        dictation.start()

        if SettingsStore.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.showSettingsWindow()
            }
        }
    }

    func showMainWindow() {
        if let mainWindowController {
            mainWindowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = ContentView(onOpenSettings: { [weak self] in
            self?.showSettingsWindow()
        })
        .environmentObject(settings)
        .environmentObject(dictation)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Ramblr"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1)
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("RamblrMainWindow")

        let controller = NSWindowController(window: window)
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettingsWindow() {
        if let settingsWindowController {
            settingsWindowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = SettingsView()
            .environmentObject(settings)
            .environmentObject(dictation)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1)
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("RamblrSettingsWindow")

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: "Ramblr"
        )
        button.image?.isTemplate = true
        button.toolTip = "Ramblr — hold \(settings.shortcut.displayString) to dictate"
        statusItem.menu = menu
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let shortcutItem = NSMenuItem(
            title: "Dictation: \(settings.shortcut.displayString)",
            action: nil,
            keyEquivalent: ""
        )
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        let composeItem = NSMenuItem(
            title: "Compose: \(settings.composeShortcut.displayString)",
            action: nil,
            keyEquivalent: ""
        )
        composeItem.isEnabled = false
        menu.addItem(composeItem)

        menu.addItem(.separator())

        let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micItem.submenu = microphoneSubmenu()
        menu.addItem(micItem)

        let pasteItem = NSMenuItem(
            title: "Paste Last Transcript",
            action: #selector(pasteLastTranscript),
            keyEquivalent: ""
        )
        pasteItem.target = self
        pasteItem.isEnabled = settings.lastTranscript != nil
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let showItem = NSMenuItem(
            title: "Show Ramblr",
            action: #selector(showRamblr),
            keyEquivalent: "o"
        )
        showItem.target = self
        showItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Ramblr",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func microphoneSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let devices = MicrophoneDeviceManager.listInputDevices()

        let auto = NSMenuItem(
            title: autoDetectTitle(devices: devices),
            action: #selector(selectAutoMicrophone),
            keyEquivalent: ""
        )
        auto.target = self
        auto.state = settings.microphoneUID == nil ? .on : .off
        submenu.addItem(auto)

        if !devices.isEmpty {
            submenu.addItem(.separator())
        }

        for device in devices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectMicrophone(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.id
            item.state = settings.microphoneUID == device.id ? .on : .off
            submenu.addItem(item)
        }

        return submenu
    }

    private func autoDetectTitle(devices: [MicrophoneDevice]) -> String {
        if let uid = MicrophoneDeviceManager.defaultInputDeviceUID(),
           let device = devices.first(where: { $0.id == uid }) {
            return "Auto-detect (\(device.name))"
        }
        return "Auto-detect (System Default)"
    }

    private func observeState() {
        dictation.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
            .store(in: &cancellables)

        settings.$shortcut
            .combineLatest(settings.$composeShortcut)
            .receive(on: RunLoop.main)
            .sink { [weak self] dictationShortcut, _ in
                self?.statusItem.button?.toolTip =
                    "Ramblr — hold \(dictationShortcut.displayString) to dictate"
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for state: DictationState) {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch state {
        case .idle, .complete, .notice:
            symbol = "mic.fill"
        case .preparing:
            symbol = "mic"
        case .recording:
            symbol = "mic.fill"
        case .processing:
            symbol = "ellipsis.circle"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Ramblr")
        button.image?.isTemplate = true

        switch state {
        case .recording:
            button.contentTintColor = .systemRed
        case .complete:
            button.contentTintColor = RamblrTheme.accentNS
        default:
            button.contentTintColor = nil
        }
    }

    @objc private func selectAutoMicrophone() {
        settings.microphoneUID = nil
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        settings.microphoneUID = uid
    }

    @objc private func pasteLastTranscript() {
        guard let text = settings.lastTranscript else { return }
        FocusPasteService.copyToClipboard(text)
        if FocusPasteService.hasEditableFocus() {
            FocusPasteService.paste(text)
        } else {
            ToastPresenter.shared.show(message: "Last transcript copied to the clipboard.")
        }
    }

    @objc private func showRamblr() {
        showMainWindow()
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
