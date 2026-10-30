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

        minimizeUnwantedProfiles(plan)

        var order: [String] = []
        var byDisplay: [String: [Placement]] = [:]
        for placement in plan.show {
            if byDisplay[placement.displayUUID] == nil { order.append(placement.displayUUID) }
            byDisplay[placement.displayUUID, default: []].append(placement)
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for uuid in order {
            guard let info = displays.first(where: { $0.uuid == uuid }), let apps = byDisplay[uuid] else { continue }
            let visible = info.screen.visibleFrame
            let width = visible.width / CGFloat(apps.count)
            for (index, placement) in apps.enumerated() {
                // AppKit (bottom-left origin) -> Accessibility (top-left origin of primary screen)
                let rect = CGRect(x: visible.minX + CGFloat(index) * width,
                                  y: primaryHeight - visible.maxY,
                                  width: width, height: visible.height)
                place(placement, in: rect)
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

    /// Minimizes windows of configured browser profiles the target does not use.
    /// Windows of profiles that are not configured anywhere are never touched.
    private static func minimizeUnwantedProfiles(_ plan: SwitchPlan) {
        for (bundleID, known) in plan.knownProfiles {
            let wanted = Set(plan.show.filter { $0.bundleID == bundleID }.compactMap(\.profile))
            guard !wanted.isEmpty,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
            for window in windows(pid: app.processIdentifier, includeMinimized: false) {
                if let profile = ChromeProfiles.profile(inTitle: title(of: window), among: known), !wanted.contains(profile) {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                }
            }
        }
    }

    private static func place(_ placement: Placement, in rect: CGRect) {
        let bundleID = placement.bundleID
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.unhide()
            if let profile = placement.profile {
                let mine = profileWindows(pid: app.processIdentifier, bundleID: bundleID, profile: profile)
                if mine.isEmpty {
                    launchProfile(profile, pid: app.processIdentifier, bundleID: bundleID, rect: rect)
                } else {
                    mine.forEach { frame($0, to: rect, unminimize: true) }
                }
            } else {
                setWindows(pid: app.processIdentifier, to: rect)
            }
            return
        }
        if let profile = placement.profile {
            launchProfile(profile, pid: nil, bundleID: bundleID, rect: rect)
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

    private static func launchProfile(_ profile: String, pid: pid_t?, bundleID: String, rect: CGRect) {
        ChromeProfiles.launch(name: profile)
        // The new window appears a moment later; look it up again and tile it.
        for delay in [1.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
                profileWindows(pid: app.processIdentifier, bundleID: bundleID, profile: profile)
                    .forEach { frame($0, to: rect, unminimize: true) }
            }
        }
    }

    private static func profileWindows(pid: pid_t, bundleID: String, profile: String) -> [AXUIElement] {
        windows(pid: pid, includeMinimized: true).filter { window in
            ChromeProfiles.profileName(inTitle: title(of: window)) == profile
        }
    }

    private static func title(of window: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        return (value as? String) ?? ""
    }

    private static func standardWindows(pid: pid_t) -> [AXUIElement] {
        windows(pid: pid, includeMinimized: false)
    }

    private static func windows(pid: pid_t, includeMinimized: Bool) -> [AXUIElement] {
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
            return (subrole as? String) == (kAXStandardWindowSubrole as String)
                && (includeMinimized || (minimized as? Bool) != true)
        }
    }

    private static func setWindows(pid: pid_t, to rect: CGRect) {
        standardWindows(pid: pid).forEach { frame($0, to: rect, unminimize: false) }
    }

    private static func frame(_ window: AXUIElement, to rect: CGRect, unminimize: Bool) {
        if unminimize { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        var size = rect.size
        var origin = rect.origin
        // size, position, size again: avoids clamping when moving across displays
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
        if let v = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v) }
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}
