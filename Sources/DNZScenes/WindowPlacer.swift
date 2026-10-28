import AppKit
import ApplicationServices
import ScenesCore

enum WindowPlacer {
    static func isTrusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    /// Hides other contexts' apps, then shows/launches target apps tiled side by side per display.
    static func apply(_ plan: SwitchPlan, displays: [DisplayInfo]) {
        for bundleID in plan.hide {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.hide() }
        }

        var order: [String] = []
        var byDisplay: [String: [String]] = [:]
        for placement in plan.show {
            if byDisplay[placement.displayUUID] == nil { order.append(placement.displayUUID) }
            byDisplay[placement.displayUUID, default: []].append(placement.bundleID)
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for uuid in order {
            guard let info = displays.first(where: { $0.uuid == uuid }), let apps = byDisplay[uuid] else { continue }
            let visible = info.screen.visibleFrame
            let width = visible.width / CGFloat(apps.count)
            for (index, bundleID) in apps.enumerated() {
                // AppKit (bottom-left origin) -> Accessibility (top-left origin of primary screen)
                let rect = CGRect(x: visible.minX + CGFloat(index) * width,
                                  y: primaryHeight - visible.maxY,
                                  width: width, height: visible.height)
                place(bundleID: bundleID, in: rect)
            }
        }
    }

    static func firstWindowFrame(pid: pid_t) -> CGRect? {
        guard let window = standardWindows(pid: pid).first else { return nil }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID(),
              AXValueGetValue(unsafeBitCast(posRef, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(sizeRef, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    // MARK: - private

    private static func place(bundleID: String, in rect: CGRect) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.unhide()
            setWindows(pid: app.processIdentifier, to: rect)
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("DNZ-Scenes: app not found: %@", bundleID)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            guard let app else {
                NSLog("DNZ-Scenes: launch failed for %@: %@", bundleID, String(describing: error))
                return
            }
            let pid = app.processIdentifier
            // Windows appear a moment after launch; try twice.
            for delay in [1.5, 4.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard !app.isTerminated else { return }
                    setWindows(pid: pid, to: rect)
                }
            }
        }
    }

    private static func standardWindows(pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)  // a hung app must not freeze the menu bar app
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.filter { window in
            var subrole: CFTypeRef?
            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
            return (subrole as? String) == (kAXStandardWindowSubrole as String) && (minimized as? Bool) != true
        }
    }

    private static func setWindows(pid: pid_t, to rect: CGRect) {
        for window in standardWindows(pid: pid) {
            var size = rect.size
            var origin = rect.origin
            // size, position, size again: avoids clamping when moving across displays
            if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
            if let v = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v) }
            if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }
}
