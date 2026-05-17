//
//  GlobalHotKey.swift
//  Inspect
//
//  Thin Swift wrapper around Carbon's RegisterEventHotKey API.
//
//  Why Carbon and not NSEvent.addGlobalMonitorForEvents: a global
//  monitor only OBSERVES key events; it can't consume them, so the
//  underlying app still receives the keypress. RegisterEventHotKey
//  actually claims the key combo system-wide.
//
//  All hot-key instances share a single installed Carbon event
//  handler — `installHandlerIfNeeded()` is idempotent. The static
//  `registry` lets the handler look up which Swift instance owns
//  a given hot-key ID and invoke its closure.
//

import Carbon.HIToolbox
import Foundation

/// Append a single diagnostic line to ~/Library/Logs/Inspect-launch.log.
/// Plain file IO is the most reliable signal we have — NSLog doesn't
/// surface in `log show` for this app under macOS 26 / Xcode 26 betas,
/// and we need to see exactly what RegisterEventHotKey returned + when
/// the Carbon handler fires.
fileprivate func inspectDiag(_ msg: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let path = ("~/Library/Logs/Inspect-launch.log" as NSString).expandingTildeInPath
    let line = "[\(stamp)] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

final class GlobalHotKey {

    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled: Bool = false

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?

    init() {
        self.id = Self.nextID
        Self.nextID += 1
        Self.installHandlerIfNeeded()
    }

    deinit { unregister() }

    func register(keyCode: UInt32, modifiers: UInt32, _ handler: @escaping () -> Void) {
        unregister()
        self.handler = handler
        Self.registry[id] = self

        var ref: EventHotKeyRef?
        // 4-char signature 'LPE\0' to identify our hot-keys in any
        // future diagnostic output. Not user-visible.
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C50_4500), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            self.hotKeyRef = ref
            inspectDiag(String(format: "hotkey registered keyCode=0x%02X mods=0x%X id=%u",
                               Int(keyCode), Int(modifiers), Int(id)))
        } else {
            inspectDiag(String(format: "RegisterEventHotKey FAILED status=%d keyCode=0x%02X mods=0x%X",
                               Int(status), Int(keyCode), Int(modifiers)))
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        Self.registry.removeValue(forKey: id)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                DispatchQueue.main.async {
                    inspectDiag("hotkey FIRED id=\(hotKeyID.id)")
                    GlobalHotKey.registry[hotKeyID.id]?.handler?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        if status == noErr {
            handlerInstalled = true
            inspectDiag("InstallEventHandler succeeded")
        } else {
            inspectDiag("InstallEventHandler FAILED status=\(status)")
        }
    }
}
