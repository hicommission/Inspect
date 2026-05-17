//
//  HotKeyDescription.swift
//  Inspect
//
//  Converts (keyCode, Carbon modifier mask) → human-readable
//  shortcut strings like "⌃⌥⌘L" and back-converts NSEvent modifier
//  flags to the Carbon bitmask we hand to RegisterEventHotKey.
//
//  Key-code → label lookup is a hand-rolled table covering the
//  keys a user would realistically bind: letters, digits, function
//  keys, arrows, common punctuation. Unknown codes fall back to
//  "Key 0x25" so we never silently lose the user's choice.
//

import AppKit
import Carbon.HIToolbox

enum HotKeyDescription {

    // MARK: - Display

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierString(carbonMask: modifiers) + keyLabel(for: keyCode)
    }

    static func modifierString(carbonMask: UInt32) -> String {
        var s = ""
        if carbonMask & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonMask & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonMask & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonMask & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    static func keyLabel(for keyCode: UInt32) -> String {
        keyCodeToLabel[keyCode] ?? String(format: "Key 0x%02X", keyCode)
    }

    // MARK: - Modifier conversion

    /// AppKit's NSEvent.ModifierFlags bitmask → Carbon's UInt32
    /// modifier mask suitable for RegisterEventHotKey.
    static func carbonMask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option)  { mask |= UInt32(optionKey)  }
        if flags.contains(.shift)   { mask |= UInt32(shiftKey)   }
        if flags.contains(.command) { mask |= UInt32(cmdKey)     }
        return mask
    }

    /// Validation rule for a recorded shortcut: must include at
    /// least one of ⌃ / ⌥ / ⌘. (Shift alone is rejected because
    /// "⇧A" would just be a capital A and would steal it from
    /// every text field on the system.) Function keys + special
    /// keys are exempted — F5 alone is a legitimate global hotkey.
    static func isValidShortcut(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let nonShiftMods = UInt32(controlKey | optionKey | cmdKey)
        if modifiers & nonShiftMods != 0 { return true }
        // Function keys + media keys are allowed bare.
        return isFunctionOrSpecialKey(keyCode)
    }

    private static func isFunctionOrSpecialKey(_ keyCode: UInt32) -> Bool {
        let fKeys: Set<UInt32> = [
            UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
            UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
            UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
            UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
            UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20)
        ]
        return fKeys.contains(keyCode)
    }

    // MARK: - Key-code → label table

    private static let keyCodeToLabel: [UInt32: String] = {
        var m: [UInt32: String] = [:]

        // Letters
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"),
            (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"),
            (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"),
            (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"),
            (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"), (kVK_ANSI_U, "U"),
            (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z")
        ]
        letters.forEach { m[UInt32($0.0)] = $0.1 }

        // Digits
        let digits: [(Int, String)] = [
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"),
            (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"),
            (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"),
            (kVK_ANSI_9, "9")
        ]
        digits.forEach { m[UInt32($0.0)] = $0.1 }

        // Function keys
        let fkeys: [(Int, String)] = [
            (kVK_F1,  "F1"),  (kVK_F2,  "F2"),  (kVK_F3,  "F3"),
            (kVK_F4,  "F4"),  (kVK_F5,  "F5"),  (kVK_F6,  "F6"),
            (kVK_F7,  "F7"),  (kVK_F8,  "F8"),  (kVK_F9,  "F9"),
            (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
            (kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"),
            (kVK_F16, "F16"), (kVK_F17, "F17"), (kVK_F18, "F18"),
            (kVK_F19, "F19"), (kVK_F20, "F20")
        ]
        fkeys.forEach { m[UInt32($0.0)] = $0.1 }

        // Special keys
        m[UInt32(kVK_Space)]        = "Space"
        m[UInt32(kVK_Return)]       = "↩"
        m[UInt32(kVK_Tab)]          = "⇥"
        m[UInt32(kVK_Delete)]       = "⌫"
        m[UInt32(kVK_ForwardDelete)] = "⌦"
        m[UInt32(kVK_Escape)]       = "⎋"
        m[UInt32(kVK_UpArrow)]      = "↑"
        m[UInt32(kVK_DownArrow)]    = "↓"
        m[UInt32(kVK_LeftArrow)]    = "←"
        m[UInt32(kVK_RightArrow)]   = "→"
        m[UInt32(kVK_Home)]         = "↖"
        m[UInt32(kVK_End)]          = "↘"
        m[UInt32(kVK_PageUp)]       = "⇞"
        m[UInt32(kVK_PageDown)]     = "⇟"

        // Punctuation
        m[UInt32(kVK_ANSI_Minus)]     = "-"
        m[UInt32(kVK_ANSI_Equal)]     = "="
        m[UInt32(kVK_ANSI_LeftBracket)]  = "["
        m[UInt32(kVK_ANSI_RightBracket)] = "]"
        m[UInt32(kVK_ANSI_Backslash)] = "\\"
        m[UInt32(kVK_ANSI_Semicolon)] = ";"
        m[UInt32(kVK_ANSI_Quote)]     = "'"
        m[UInt32(kVK_ANSI_Comma)]     = ","
        m[UInt32(kVK_ANSI_Period)]    = "."
        m[UInt32(kVK_ANSI_Slash)]     = "/"
        m[UInt32(kVK_ANSI_Grave)]     = "`"

        return m
    }()
}
