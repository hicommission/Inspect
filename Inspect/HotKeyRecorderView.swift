//
//  HotKeyRecorderView.swift
//  Inspect
//
//  A single-line "click-to-record-a-shortcut" control. Looks like
//  a rounded text field; clicking puts it into recording mode, the
//  next key combo replaces the bound shortcut, and Esc cancels.
//
//  Validation goes through `HotKeyDescription.isValidShortcut` so
//  you can't accidentally bind a bare letter (which would steal it
//  from every text field) — modifiers are required for most keys,
//  but function keys may be bound on their own.
//

import AppKit
import Carbon.HIToolbox

final class HotKeyRecorderView: NSView {

    var keyCode: UInt32
    var modifiers: UInt32   // Carbon mask

    /// Fired after a successful recording with the new (keyCode,
    /// carbonModifiers) — the controller persists + re-registers.
    var onChange: ((UInt32, UInt32) -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) }
    }

    private let label = NSTextField(labelWithString: "")

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 28))
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        refreshLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { isRecording = false; refreshLabel() }
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        label.stringValue = "Press shortcut…"
        label.textColor = .secondaryLabelColor
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }

        // Esc cancels without saving.
        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            refreshLabel()
            return
        }

        // Delete clears (unbinds — caller can decide to fall back
        // to default; for now we just keep the previous value and
        // exit recording). Treat Delete + no modifiers as a reset
        // signal so the user has an escape hatch.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonMods = HotKeyDescription.carbonMask(from: flags)
        let newKeyCode = UInt32(event.keyCode)

        guard HotKeyDescription.isValidShortcut(keyCode: newKeyCode, modifiers: carbonMods) else {
            // Flash and stay in recording mode so the user can try again.
            NSSound.beep()
            return
        }

        keyCode = newKeyCode
        modifiers = carbonMods
        isRecording = false
        refreshLabel()
        onChange?(keyCode, modifiers)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        layer?.borderColor = isRecording
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.borderWidth = isRecording ? 2 : 1
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func refresh() {
        refreshLabel()
    }

    private func refreshLabel() {
        if isRecording {
            label.stringValue = "Press shortcut…"
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = HotKeyDescription.displayString(
                keyCode: keyCode, modifiers: modifiers
            )
            label.textColor = .labelColor
        }
    }
}
