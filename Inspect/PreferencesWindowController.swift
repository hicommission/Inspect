//
//  PreferencesWindowController.swift
//  Inspect
//
//  Tiny Preferences window: a hotkey recorder + a "Reset to
//  Default" button + a one-line hint about ↑ / ↓ for zoom. Posts
//  `.inspectHotKeyDidChange` on save so AppDelegate can rebind the
//  Carbon hotkey without restarting.
//

import AppKit

final class PreferencesWindowController: NSWindowController {

    private let recorder: HotKeyRecorderView

    init() {
        let recorder = HotKeyRecorderView(
            keyCode: InspectDefaults.hotKeyCode,
            modifiers: InspectDefaults.hotKeyModifiers
        )
        self.recorder = recorder

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Inspect Preferences"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        window.contentView = buildContent(recorder: recorder)
        recorder.onChange = { [weak self] keyCode, mods in
            self?.persist(keyCode: keyCode, modifiers: mods)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent(recorder: HotKeyRecorderView) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))

        let title = NSTextField(labelWithString: "Toggle Inspect Shortcut")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        recorder.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(
            title: "Reset to Default",
            target: self,
            action: #selector(handleReset(_:))
        )
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        let hintText = """
            Click the field, then press the key combo you want.
            Esc cancels recording.

            While the inspect is visible:
                ↑  zoom in    ↓  zoom out    Esc  dismiss
            """
        let hint = NSTextField(wrappingLabelWithString: hintText)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(title)
        container.addSubview(recorder)
        container.addSubview(resetButton)
        container.addSubview(hint)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            recorder.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            recorder.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            recorder.widthAnchor.constraint(equalToConstant: 180),
            recorder.heightAnchor.constraint(equalToConstant: 28),

            resetButton.centerYAnchor.constraint(equalTo: recorder.centerYAnchor),
            resetButton.leadingAnchor.constraint(equalTo: recorder.trailingAnchor, constant: 12),

            hint.topAnchor.constraint(equalTo: recorder.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])

        return container
    }

    private func persist(keyCode: UInt32, modifiers: UInt32) {
        InspectDefaults.hotKeyCode = keyCode
        InspectDefaults.hotKeyModifiers = modifiers
        NotificationCenter.default.post(name: .inspectHotKeyDidChange, object: nil)
    }

    @objc private func handleReset(_ sender: Any?) {
        InspectDefaults.reset()
        recorder.keyCode = InspectDefaults.defaultKeyCode
        recorder.modifiers = InspectDefaults.defaultModifiers
        recorder.refresh()
        NotificationCenter.default.post(name: .inspectHotKeyDidChange, object: nil)
    }
}
