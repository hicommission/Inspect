//
//  MagnifierController.swift
//  Inspect
//
//  Owns the magnifier panel + view and the per-frame redraw timer.
//  Behavior model (rev May 2026):
//
//   * `toggle()` — show or hide the loupe. Hotkey + URL scheme
//     converge here.
//   * On `show()` the panel appears CENTERED ON THE CURRENT MOUSE
//     POSITION exactly once, then stays put. The user drags it by
//     clicking inside the loupe disc (`isMovableByWindowBackground
//     = true` on MagnifierPanel) — anywhere outside the disc passes
//     to whatever app is underneath.
//   * NO auto-hide on focus change. The loupe stays visible across
//     app switches so popovers / menus / drag-and-drop don't
//     dismiss it. Only Esc, the hotkey, or quitting Inspect closes
//     it.
//   * The 30 Hz timer no longer follows the mouse — it just marks
//     the view for redisplay so animated content under a stationary
//     loupe (videos, spinning indicators) keeps updating.
//

import AppKit

final class MagnifierController {

    /// Panel diameter in points. 420 pt ≈ 5" on a typical Mac
    /// Retina display — matches the user's "about 5 inches" ask.
    private let panelSize: CGFloat = 420

    private var panel: MagnifierPanel?
    private var view: MagnifierView?
    private var redrawTimer: Timer?

    /// Persist the user's last zoom level between toggles in this
    /// process lifetime. Not saved across launches — keeping the
    /// utility stateless on disk.
    private var lastZoom: CGFloat = 2.0

    deinit { hide() }

    var isShown: Bool { panel?.isVisible == true }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    // MARK: - Show / hide

    private func show() {
        let panel = MagnifierPanel(size: panelSize)
        let view = MagnifierView(
            frame: NSRect(x: 0, y: 0, width: panelSize, height: panelSize)
        )
        view.panel = panel
        view.zoomFactor = lastZoom
        view.onDismiss = { [weak self] in self?.hide() }
        panel.contentView = view

        // One-time placement at the current mouse location. After
        // this, panel.frame.origin is wherever the user drags it.
        positionPanel(panel, atMouse: NSEvent.mouseLocation)

        panel.orderFrontRegardless()
        // DELIBERATELY no makeKey() — focus stays with whichever app
        // the user is working in, so popovers (voice picker, menus)
        // don't dismiss the moment the loupe appears. Arrow-key zoom
        // requires clicking the loupe first; scroll-wheel zoom works
        // immediately without focus (see MagnifierView.scrollWheel).

        self.panel = panel
        self.view = view

        // 30 Hz redraw — keeps animated content under the loupe
        // current. NOT tied to mouse position anymore.
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0,
                                            repeats: true) { [weak self] _ in
            self?.view?.needsDisplay = true
        }
    }

    private func hide() {
        if let view = view {
            lastZoom = view.zoomFactor
        }
        redrawTimer?.invalidate()
        redrawTimer = nil
        panel?.orderOut(nil)
        panel = nil
        view = nil
    }

    private func positionPanel(_ panel: MagnifierPanel, atMouse mouse: NSPoint) {
        let size = panel.frame.size
        let origin = NSPoint(
            x: mouse.x - size.width / 2,
            y: mouse.y - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
