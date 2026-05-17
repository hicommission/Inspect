//
//  AppDelegate.swift
//  Inspect — a global-hotkey magnifying glass for macOS
//
//  Architecture:
//   * Menu-bar only (LSUIElement = YES). No dock icon, no main window.
//   * Carbon RegisterEventHotKey installs the global ⌃⌥⌘L toggle.
//   * MagnifierController owns the floating panel + per-frame redraw.
//
//  Screen-capture path uses CGWindowListCreateImage with
//  optionOnScreenBelowWindow filtered by our own windowNumber, which
//  captures everything beneath the inspect without ever including the
//  inspect itself. First run prompts the user to grant Screen Recording
//  permission in System Settings → Privacy & Security.
//

import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let hotKey = GlobalHotKey()
    private let magnifier = MagnifierController()
    private var preferences: PreferencesWindowController?
    private var hotKeyMenuItem: NSMenuItem?
    /// NSEvent global key monitor — the reliable path on macOS 26.
    /// Carbon RegisterEventHotKey silently swallows physical key events
    /// for ad-hoc / Apple-Development-signed apps on this OS, so we
    /// fall back to the AX-permission-gated global monitor which sees
    /// every keydown including physical ones. Requires Accessibility
    /// permission for the app (granted in Privacy & Security).
    private var globalKeyMonitor: Any?

    /// URL-scheme invocation fallback. Triggered by:
    ///     open inspect://toggle
    /// Lets us validate the magnifier path even when the menu bar
    /// item is hidden (e.g. behind the MacBook notch) and physical
    /// hotkeys aren't reaching Carbon for some reason. Hooked up
    /// via `application(_:open:)` plus a CFBundleURLTypes entry in
    /// Info.plist registering the `inspect://` scheme.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            appendDiag("URL open: \(url.absoluteString)")
            switch url.host?.lowercased() ?? "" {
            case "toggle":
                magnifier.toggle()
            case "preferences":
                showPreferences()
            default:
                break
            }
        }
    }

    /// Trigger macOS's standard Accessibility-permission prompt the
    /// first time Inspect starts without the grant. AXIsProcessTrusted
    /// is required for NSEvent.addGlobalMonitorForEvents on key
    /// events; without it, the monitor silently never fires. Prompting
    /// surfaces this to the user rather than letting it appear as
    /// "the hotkey just doesn't work".
    private func promptAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        appendDiag("AXIsProcessTrusted=\(trusted)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Diagnostic: write a timestamped marker file so we can
        // independently verify the delegate actually fires when
        // NSLog output isn't surfacing in the unified log.
        let stamp = ISO8601DateFormatter().string(from: Date())
        let path = ("~/Library/Logs/Inspect-launch.log" as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let line = "[\(stamp)] applicationDidFinishLaunching\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path),
               let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        NSLog("Inspect: applicationDidFinishLaunching ENTERED")

        installStatusItem()
        promptAccessibilityIfNeeded()
        installHotKey()
        registerAsLoginItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyDidChange),
            name: .inspectHotKeyDidChange,
            object: nil
        )

        NSLog("Inspect: applicationDidFinishLaunching COMPLETED")
        appendDiag("setup completed")
    }

    private func appendDiag(_ msg: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let path = ("~/Library/Logs/Inspect-launch.log" as NSString).expandingTildeInPath
        let line = "[\(stamp)] \(msg)\n"
        guard let data = line.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path))
        else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    }

    /// Register self as a Login Item via SMAppService (macOS 13+).
    /// Idempotent — calling on an already-registered app is a no-op.
    /// Silent on failure: SMAppService refuses to register apps run
    /// from non-standard locations (DerivedData, Downloads), which
    /// is expected during development; the install lands the bundle
    /// in /Applications where registration succeeds on next launch.
    private func registerAsLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                NSLog("Inspect: SMAppService.register failed: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Menu-bar item

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Force visible — defaults can persist isVisible=false across
        // launches if an earlier ad-hoc build set it that way.
        statusItem.isVisible = true
        statusItem.autosaveName = "InspectStatusItem"
        statusItem.behavior = []

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "magnifyingglass.circle.fill",
                accessibilityDescription: "Inspect"
            )
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "Inspect — magnifier loupe (⌃⌥⌘L)"
            appendDiag("statusItem installed  visible=\(statusItem.isVisible) hasImage=\(button.image != nil) length=\(statusItem.length)")
        } else {
            appendDiag("statusItem.button is NIL — status item creation failed")
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: toggleItemTitle(),
            action: #selector(toggleInspectFromMenu),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        hotKeyMenuItem = toggleItem

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(
            title: "About Inspect",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Inspect",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func toggleItemTitle() -> String {
        let shortcut = HotKeyDescription.displayString(
            keyCode: InspectDefaults.hotKeyCode,
            modifiers: InspectDefaults.hotKeyModifiers
        )
        return "Toggle Inspect  \(shortcut)"
    }

    // MARK: - Hotkey

    private func installHotKey() {
        let keyCode = InspectDefaults.hotKeyCode
        let modifiers = InspectDefaults.hotKeyModifiers

        // Path 1 — Carbon RegisterEventHotKey. Doesn't fire for
        // physical keypresses on macOS 26 with our signature, but
        // we keep it registered as a no-op safety net for the
        // synthesized-keystroke case (osascript et al).
        hotKey.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.magnifier.toggle()
        }

        // Path 2 — NSEvent global monitor. AX-gated. Fires for all
        // keydowns delivered to OTHER apps (Inspect is LSUIElement
        // and never frontmost, so this catches everything). The
        // monitor cannot consume events; the matching ⌃⌥⌘L still
        // passes through to whatever app is frontmost, but for an
        // uncommon combo like this no app cares.
        if let prior = globalKeyMonitor {
            NSEvent.removeMonitor(prior)
            globalKeyMonitor = nil
        }
        let expectedMods = Self.cocoaFlags(fromCarbon: modifiers)
        let modMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let eventMods = event.modifierFlags.intersection(modMask)
            if UInt32(event.keyCode) == keyCode && eventMods == expectedMods {
                self.appendDiag("hotkey FIRED via NSEvent monitor")
                DispatchQueue.main.async {
                    self.magnifier.toggle()
                }
            }
        }
        appendDiag("NSEvent global monitor installed for keyCode=\(keyCode) mods=\(modifiers)")
    }

    /// Carbon modifier mask → NSEvent.ModifierFlags subset.
    private static func cocoaFlags(fromCarbon mask: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mask & UInt32(controlKey) != 0 { flags.insert(.control) }
        if mask & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if mask & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        if mask & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        return flags
    }

    @objc private func hotKeyDidChange() {
        // Re-register Carbon hotkey with new combo from defaults
        // and refresh the menu item's shortcut hint.
        installHotKey()
        hotKeyMenuItem?.title = toggleItemTitle()
    }

    // MARK: - Menu actions

    @objc private func toggleInspectFromMenu() {
        magnifier.toggle()
    }

    @objc private func showPreferences() {
        if preferences == nil {
            preferences = PreferencesWindowController()
        }
        preferences?.show()
    }

    @objc private func showAbout() {
        let shortcut = HotKeyDescription.displayString(
            keyCode: InspectDefaults.hotKeyCode,
            modifiers: InspectDefaults.hotKeyModifiers
        )
        let alert = NSAlert()
        alert.messageText = "Inspect"
        alert.informativeText = """
            A circular magnifying glass that follows your mouse.

            Hotkey: \(shortcut) to show / hide  (change in Preferences)
            ↑ / ↓ to zoom in / out
            Esc to dismiss

            First run will request Screen Recording permission in
            System Settings → Privacy & Security.
            """
        alert.alertStyle = .informational
        alert.runModal()
    }
}
