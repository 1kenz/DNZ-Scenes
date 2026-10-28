import AppKit
import ScenesCore

/// Radial profile picker (like an Actions Ring): appears at the mouse pointer, click a wedge to switch.
final class ProfileRingController {
    private var panel: RingPanel?
    var onSelect: ((String) -> Void)?

    func show(contexts: [Context], activeID: String?) {
        close()
        guard !contexts.isEmpty else { return }
        let size: CGFloat = 380
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x - size / 2, y: mouse.y - size / 2)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size)
        }
        let panel = RingPanel(contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = RingView(frame: NSRect(origin: .zero, size: panel.frame.size),
                            contexts: contexts, activeID: activeID)
        view.onPick = { [weak self] id in
            self?.close()
            self?.onSelect?(id)
        }
        view.onCancel = { [weak self] in self?.close() }
        panel.onResign = { [weak self] in self?.close() }
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        self.panel = panel
    }

    func close() {
        panel?.onResign = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class RingPanel: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

private final class RingView: NSView {
    private let contexts: [Context]
    private let activeID: String?
    private var hover: Int?
    var onPick: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let innerRadius: CGFloat = 70
    private let outerRadius: CGFloat = 175

    init(frame: NSRect, contexts: [Context], activeID: String?) {
        self.contexts = contexts
        self.activeID = activeID
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var step: CGFloat { 2 * .pi / CGFloat(contexts.count) }

    /// Wedge index under a point (view coordinates), or nil in the hole / outside the ring.
    private func index(at point: NSPoint) -> Int? {
        let dx = point.x - bounds.midX
        let dy = point.y - bounds.midY
        let radius = hypot(dx, dy)
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        var angle = atan2(dx, dy)  // clockwise from top
        if angle < 0 { angle += 2 * .pi }
        let shifted = (angle + step / 2).truncatingRemainder(dividingBy: 2 * .pi)
        return min(Int(shifted / step), contexts.count - 1)
    }

    override func mouseMoved(with event: NSEvent) {
        let next = index(at: convert(event.locationInWindow, from: nil))
        if next != hover {
            hover = next
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if let i = index(at: convert(event.locationInWindow, from: nil)) {
            onPick?(contexts[i].id)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            onCancel?()
        } else if let chars = event.charactersIgnoringModifiers, let n = Int(chars),
                  n >= 1, n <= contexts.count {
            onPick?(contexts[n - 1].id)
        } else {
            super.keyDown(with: event)
        }
    }

    private func wedge(_ i: Int) -> NSBezierPath {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let gap: CGFloat = 0.02
        let startTheta = (CGFloat(i) - 0.5) * step + gap
        let endTheta = (CGFloat(i) + 0.5) * step - gap
        let startDeg = 90 - startTheta * 180 / .pi
        let endDeg = 90 - endTheta * 180 / .pi
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: outerRadius, startAngle: startDeg, endAngle: endDeg, clockwise: true)
        path.appendArc(withCenter: center, radius: innerRadius, startAngle: endDeg, endAngle: startDeg, clockwise: false)
        path.close()
        return path
    }

    private func isLight(_ color: NSColor) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.6
    }

    private func drawText(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        NSString(string: text).draw(in: rect, withAttributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let midRadius = (innerRadius + outerRadius) / 2
        for (i, context) in contexts.enumerated() {
            let color = ProfileColor.ns(context.colorHex)
            let hovered = hover == i
            let path = wedge(i)
            (hovered ? color : NSColor(white: 0.11, alpha: 0.9)).setFill()
            path.fill()
            if context.id == activeID {
                color.setStroke()
                path.lineWidth = 3
                path.stroke()
            }
            let theta = CGFloat(i) * step
            let cx = center.x + midRadius * sin(theta)
            let cy = center.y + midRadius * cos(theta)
            let textColor: NSColor = hovered ? (isLight(color) ? .black : .white) : .white
            drawText("\(i + 1)", font: .systemFont(ofSize: 18, weight: .bold), color: textColor,
                     in: NSRect(x: cx - 46, y: cy + 1, width: 92, height: 22))
            drawText(context.displayName, font: .systemFont(ofSize: 11.5, weight: .medium), color: textColor,
                     in: NSRect(x: cx - 46, y: cy - 19, width: 92, height: 16))
        }
        let hole = NSBezierPath(ovalIn: NSRect(x: center.x - innerRadius + 8, y: center.y - innerRadius + 8,
                                               width: (innerRadius - 8) * 2, height: (innerRadius - 8) * 2))
        NSColor(white: 0.08, alpha: 0.92).setFill()
        hole.fill()
        let shown = hover.map { contexts[$0] } ?? contexts.first(where: { $0.id == activeID })
        drawText(shown?.displayName ?? "Scenes", font: .systemFont(ofSize: 14, weight: .semibold), color: .white,
                 in: NSRect(x: center.x - 50, y: center.y - 9, width: 100, height: 18))
    }
}
