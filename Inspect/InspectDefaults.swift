//
//  InspectDefaults.swift
//  Inspect
//
//  Typed access to UserDefaults for the user-configurable hotkey.
//  Stored as a (keyCode, carbonModifiers) pair so we can hand it
//  straight to RegisterEventHotKey without re-encoding at every
//  read.
//
//  Defaults — keyCode = L, modifiers = ⌃⌥⌘. Reset via `reset()`.
//

import Carbon.HIToolbox
import Foundation

enum InspectDefaults {

    private static let keyCodeKey   = "InspectHotKeyKeyCode"
    private static let modifiersKey = "InspectHotKeyModifiers"

    static let defaultKeyCode:   UInt32 = UInt32(kVK_ANSI_L)
    static let defaultModifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)

    static var hotKeyCode: UInt32 {
        get {
            if let v = UserDefaults.standard.object(forKey: keyCodeKey) as? Int {
                return UInt32(v)
            }
            return defaultKeyCode
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: keyCodeKey) }
    }

    static var hotKeyModifiers: UInt32 {
        get {
            if let v = UserDefaults.standard.object(forKey: modifiersKey) as? Int {
                return UInt32(v)
            }
            return defaultModifiers
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: modifiersKey) }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: keyCodeKey)
        UserDefaults.standard.removeObject(forKey: modifiersKey)
    }
}

/// Posted whenever the hotkey is changed in Preferences so
/// AppDelegate can unregister the old combo and register the new
/// one without restarting the app.
extension Notification.Name {
    static let inspectHotKeyDidChange = Notification.Name("InspectHotKeyDidChange")
}
