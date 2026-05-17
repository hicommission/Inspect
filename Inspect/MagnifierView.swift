//
//  MagnifierView.swift
//  Inspect
//
//  NSView that, on every redraw, captures the screen region behind
//  itself (filtered to exclude our own window) and draws it scaled
//  up inside a circular clip path. The result looks like a glass
//  magnifying inspect — circular bezel, transparent corners, sharp
//  magnified content inside.
//
//  Key handling: ↑ / ↓ adjust `zoomFactor`, Esc hides the panel.
//  These shortcuts only fire while the panel is the key window
//  (toggled via the global hotkey).
//

import AppKit
import Carbon.HIToolbox

final class MagnifierView: NSView {

    /// Min/max zoom. Min < 1 would shrink content, which defeats the
    /// purpose; max > 8 starts to render pixel mush. 0.5 step lets
    /// the user dial in granular zoom levels quickly.
    static let minZoom: CGFloat = 1.0
    static let maxZoom: CGFloat = 10.0
    static let zoomStep: CGFloat = 0.5

    var zoomFactor: CGFloat = 2.0 {
        didSet { needsDisplay = true }
    }

    /// Called by the controller when the user presses Esc inside
    /// the inspect — bubbles up so the controller can stop its
    /// per-frame redraw timer instead of just hiding the window.
    var onDismiss: (() -> Void)?

    weak var panel: MagnifierPanel?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Key handling

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            zoomFactor = min(Self.maxZoom, zoomFactor + Self.zoomStep)
        case kVK_DownArrow:
            zoomFactor = max(Self.minZoom, zoomFactor - Self.zoomStep)
        case kVK_Escape:
            onDismiss?()
        default:
            super.keyDown(with: event)
        }
    }

    /// Scroll-wheel zoom — works without the loupe being the key
    /// window, so the user's focused app (popovers, menus) stays
    /// active. Vertical-scroll up = zoom in, down = zoom out.
    /// Trackpad accumulates `scrollingDeltaY` in fractional points;
    /// we scale and clamp so a single line-by-line wheel tick maps
    /// to roughly one `zoomStep`.
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let stepped = CGFloat(delta) * 0.05
        let next = max(Self.minZoom, min(Self.maxZoom, zoomFactor + stepped))
        if next != zoomFactor {
            zoomFactor = next
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let panel = panel else { return }

        let bounds = self.bounds
        // Inset inside which the magnified content is drawn — leaves
        // a few pixels for the bezel stroke so it doesn't clip the
        // rendered image.
        let bezelInset: CGFloat = 4
        let contentRect = bounds.insetBy(dx: bezelInset, dy: bezelInset)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // ── Capture the screen region we want to magnify ──
        //
        // The size of the captured rect in screen points = contentRect
        // size / zoomFactor. We center the capture on the panel
        // center (which is the mouse position — see MagnifierController).
        let captureSize = NSSize(
            width: contentRect.width / zoomFactor,
            height: contentRect.height / zoomFactor
        )
        let panelFrame = panel.frame
        let captureRect = NSRect(
            x: panelFrame.midX - captureSize.width / 2,
            y: panelFrame.midY - captureSize.height / 2,
            width: captureSize.width,
            height: captureSize.height
        )

        if let cgImage = captureScreenBelow(panelWindowNumber: panel.windowNumber,
                                            captureRect: captureRect) {
            // Clip to circle so the corners stay transparent.
            ctx.saveGState()
            let circle = CGPath(ellipseIn: contentRect, transform: nil)
            ctx.addPath(circle)
            ctx.clip()

            // Draw the captured pixels stretched to fill the
            // content rect. The implicit scale factor =
            // contentRect.width / captureRect.width = zoomFactor.
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: contentRect)

            ctx.restoreGState()
        } else {
            // Couldn't capture — likely Screen Recording permission
            // hasn't been granted yet. Show a hint inside the inspect.
            drawPermissionHint(in: contentRect, ctx: ctx)
        }

        // ── Bezel ──
        drawBezel(in: contentRect)

        // ── Zoom indicator ──
        drawZoomLabel(in: bounds)
    }

    /// Capture the rectangle of the screen that's directly underneath
    /// our inspect, EXCLUDING our own window. CGWindowListCreateImage
    /// with `.optionOnScreenBelowWindow` filtered by our windowNumber
    /// gives us this exactly — no chicken-and-egg recursive capture.
    private func captureScreenBelow(panelWindowNumber: Int,
                                    captureRect: NSRect) -> CGImage? {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(captureRect)
        }) ?? NSScreen.main else { return nil }

        // Convert from AppKit (bottom-left origin) to CG screen
        // coords (top-left of primary display).
        let primary = NSScreen.screens.first ?? screen
        let primaryMaxY = primary.frame.maxY
        let cgRect = CGRect(
            x: captureRect.minX,
            y: primaryMaxY - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )

        let listOpts: CGWindowListOption = [.optionOnScreenBelowWindow]
        let imgOpts: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        return CGWindowListCreateImage(
            cgRect,
            listOpts,
            CGWindowID(panelWindowNumber),
            imgOpts
        )
    }

    private func drawBezel(in rect: NSRect) {
        let circle = NSBezierPath(ovalIn: rect)

        // Inner white-glass highlight ring.
        NSColor.white.withAlphaComponent(0.65).setStroke()
        circle.lineWidth = 2
        circle.stroke()

        // Outer dark ring for definition against bright content.
        let outer = NSBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2))
        NSColor.black.withAlphaComponent(0.85).setStroke()
        outer.lineWidth = 2
        outer.stroke()
    }

    private func drawZoomLabel(in bounds: NSRect) {
        let label = String(format: "%.1f×", Double(zoomFactor))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 8
        let pillRect = NSRect(
            x: bounds.midX - size.width / 2 - padding,
            y: bounds.minY + 8,
            width: size.width + padding * 2,
            height: size.height + 4
        )
        // Rounded pill background.
        NSColor.black.withAlphaComponent(0.55).setFill()
        let pill = NSBezierPath(
            roundedRect: pillRect,
            xRadius: pillRect.height / 2,
            yRadius: pillRect.height / 2
        )
        pill.fill()

        (label as NSString).draw(
            at: NSPoint(x: pillRect.minX + padding, y: pillRect.minY + 2),
            withAttributes: attrs
        )
    }

    private func drawPermissionHint(in rect: NSRect, ctx: CGContext) {
        ctx.saveGState()
        let circle = CGPath(ellipseIn: rect, transform: nil)
        ctx.addPath(circle)
        ctx.clip()
        NSColor.black.withAlphaComponent(0.85).setFill()
        rect.fill()

        let text = "Grant Screen\nRecording in\nSystem Settings"
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        ))
        ctx.restoreGState()
    }
}
