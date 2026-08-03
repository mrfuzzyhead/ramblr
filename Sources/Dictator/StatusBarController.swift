import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var windowController: NSWindowController?
    private var rightClickMenu: NSMenu?
    private var cancellables = Set<AnyCancellable>()
    private let dictation = DictationController.shared

    override init() {
        super.init()
        configureStatusItem()
        configureMenu()
        observeState()
        RecordingHUDPresenter.shared.start()
        _ = HotKeyManager.requestInputMonitoringAccess()
        _ = FocusPasteService.requestPostEventAccess()
        _ = FocusPasteService.isAccessibilityTrusted(prompt: true)
        dictation.start()

        if !HotKeyManager.hasInputMonitoringAccess() {
            DispatchQueue.main.async { [weak self] in
                self?.showMainWindow()
                FocusPasteService.openInputMonitoringSettings()
            }
        }

        // First launch / missing key: open the settings window so setup is obvious.
        if SettingsStore.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.showMainWindow()
            }
        }
    }

    func showMainWindow() {
        if let windowController {
            windowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = ContentView()
            .environmentObject(SettingsStore.shared)
            .environmentObject(dictation)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictator"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DictatorMainWindow")

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Dictator"
        )
        button.image?.isTemplate = true
        button.toolTip = "Dictator — hold ⌃⌥D to dictate"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Dictator", action: #selector(openDictator), keyEquivalent: "o")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dictator", action: #selector(quit), keyEquivalent: "q")
            .target = self
        // Menu is shown on right-click only; left-click opens the window.
        statusItem.menu = nil
        rightClickMenu = menu
    }

    private func observeState() {
        dictation.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
            .store(in: &cancellables)

        SettingsStore.shared.$shortcut
            .receive(on: RunLoop.main)
            .sink { [weak self] shortcut in
                self?.statusItem.button?.toolTip = "Dictator — hold \(shortcut.displayString) to dictate"
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for state: DictationState) {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch state {
        case .idle:
            symbol = "waveform"
        case .recording:
            symbol = "mic.fill"
        case .processing:
            symbol = "ellipsis.circle"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Dictator")
        button.image?.isTemplate = true

        if state == .recording {
            button.contentTintColor = .systemRed
        } else {
            button.contentTintColor = nil
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            showMainWindow()
            return
        }

        if event.type == .rightMouseUp {
            rightClickMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
            return
        }

        toggleMainWindow()
    }

    private func toggleMainWindow() {
        if let window = windowController?.window, window.isVisible {
            window.orderOut(nil)
            return
        }
        showMainWindow()
    }

    @objc private func openDictator() {
        showMainWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
