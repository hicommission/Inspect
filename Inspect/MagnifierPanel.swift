//
//  MagnifierPanel.swift
//  Inspect
//
//  Borderless, non-activating, transparent NSPanel that hosts the
//  circular magnifier view.
//
//  Key traits:
//   * `.nonactivatingPanel` style — can be the key window WITHOUT
//     stealing "frontmost app" status. The user's underlying app
//     stays active for menu-bar / dock / Command-Tab purposes.
//   * `canBecomeKey = true` — so the panel can capture ↑ / ↓ / Esc
//     once we call `makeKey()` programmatically. Without this
//     override, borderless windows default to `false`.
//   * `ignoresMouseEvents = true` set externally — click-through so
//     clicks on the inspect area pass to whatever's beneath, exactly
//     like a real magnifying glass on a desk.
//   * `level = .screenSaver` — floats above ALL normal windows,
//     including full-screen apps and the dock / menu-bar, so you
//     can magnify any pixel on screen.
//

import AppKit

final class MagnifierPanel: NSPanel {

    init(size: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        // Mouse events go to the panel so the user can grab it and
        // drag it to a new position. Anywhere OUTSIDE the loupe
        // they can still click through to whatever app they want
        // (those clicks miss the panel entirely).
        ignoresMouseEvents = false
        // Allow dragging by clicking ANY part of the loupe — the
        // content-view doesn't intercept mouseDown so AppKit walks
        // up to the window and starts a drag. Mirrors how HUD
        // panels work.
        isMovableByWindowBackground = true
        isMovable = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
