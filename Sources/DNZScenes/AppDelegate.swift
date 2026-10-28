import AppKit
import Carbon.HIToolbox
import SwiftUI
import ScenesCore

private final class Payload: NSObject {
    let contextID: String
    let bundleID: String
    init(_ contextID: String, _ bundleID: String = "") {
        self.contextID = contextID
        self.bundleID = bundleID
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var config = Config(displays: [:], contexts: [])
    private let hotkeys = HotkeyCenter()
    private let ring = ProfileRingController()
    private var activeID: String? = UserDefaults.standard.string(forKey: "activeContext")
    private var editorWindow: NSWindow?

    private lazy var editorModel: EditorModel = {
        let model = EditorModel(config: config)
        model.onChange = { [weak self] updated in self?.configChangedFromEditor(updated) }
        model.roleForApp = { [weak self] bundleID in self?.role(forRunning: bundleID) ?? "left" }
        return model
    }()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        ring.onSelect = { [weak self] id in self?.switchTo(id) }
        statusItem.button?.image = Self.menuBarGlyph()
        statusItem.button?.imagePosition = .imageLeft
        reloadConfig()
        _ = WindowPlacer.isTrusted(prompt: true)
    }

    // MARK: - config

    @objc private func reloadConfig() {
        let roles = Displays.roles(Displays.current())
        do {
            config = try ConfigStore.load(starterDisplays: roles)
        } catch {
            showAlert("Config error", "\(error)\n\nFile: \(ConfigStore.fileURL.path)\nThe file was not modified.")
        }
        registerHotkeys()
        updateTitle()
        syncEditor()
    }

    /// Save a change made from the menu and refresh the editor window if it is open.
    private func saveConfig() {
        do { try ConfigStore.save(config) } catch { showAlert("Could not save config", "\(error)") }
        syncEditor()
    }

    private func syncEditor() {
        if editorWindow != nil { editorModel.replace(config: config) }
    }

    /// Change coming from the editor window (names, colors, wallpapers, apps).
    private func configChangedFromEditor(_ updated: Config) {
        let oldWallpaper = config.contexts.first(where: { $0.id == activeID })?.wallpaper
        config = updated
        if let active = activeID, !updated.contexts.contains(where: { $0.id == active }) {
            activeID = nil
            UserDefaults.standard.removeObject(forKey: "activeContext")
        }
        registerHotkeys()
        do { try ConfigStore.save(config) } catch { NSLog("DNZ-Scenes: save failed: %@", String(describing: error)) }
        updateTitle()
        let newWallpaper = config.contexts.first(where: { $0.id == activeID })?.wallpaper
        if newWallpaper != oldWallpaper { Wallpaper.apply(name: newWallpaper) }
    }

    // MARK: - switching

    private func registerHotkeys() {
        hotkeys.unregisterAll()
        for (index, context) in config.contexts.enumerated() {
            guard let text = context.hotkey, let spec = HotkeySpec.parse(text),
                  let code = HotkeyCenter.keyCode(forDigit: spec.key) else { continue }
            let id = context.id
            hotkeys.register(keyCode: code, modifiers: HotkeyCenter.carbonModifiers(spec),
                             id: UInt32(index + 1)) { [weak self] in self?.switchTo(id) }
        }
        // Cycle through profiles: ctrl+opt+Right / ctrl+opt+Left (easy to bind to a mouse button).
        let cycleMods = UInt32(controlKey | optionKey)
        hotkeys.register(keyCode: UInt32(kVK_RightArrow), modifiers: cycleMods, id: 100) { [weak self] in
            self?.cycleProfile(by: 1)
        }
        hotkeys.register(keyCode: UInt32(kVK_Space), modifiers: cycleMods, id: 102) { [weak self] in
            self?.showRing()
        }
        hotkeys.register(keyCode: UInt32(kVK_LeftArrow), modifiers: cycleMods, id: 101) { [weak self] in
            self?.cycleProfile(by: -1)
        }
    }

    @objc private func showRingAction() { showRing() }

    private func showRing() {
        ring.show(contexts: config.contexts, activeID: activeID)
    }

    private func cycleProfile(by step: Int) {
        let ids = config.contexts.map(\.id)
        guard !ids.isEmpty else { return }
        let current = activeID.flatMap { ids.firstIndex(of: $0) } ?? (step > 0 ? -1 : 0)
        switchTo(ids[((current + step) % ids.count + ids.count) % ids.count])
    }

    /// dnzscenes://switch/<profile-id>, dnzscenes://next, dnzscenes://previous
    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text), url.scheme == "dnzscenes" else { return }
        switch url.host {
        case "next": cycleProfile(by: 1)
        case "previous": cycleProfile(by: -1)
        case "ring": showRing()
        case "switch":
            let id = url.lastPathComponent
            if config.contexts.contains(where: { $0.id == id }) { switchTo(id) }
        default: break
        }
    }

    private func switchTo(_ contextID: String) {
        guard WindowPlacer.isTrusted(prompt: true) else { return }
        let displays = Displays.current()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        do {
            let plan = try Switcher.plan(config: config, target: contextID, runningApps: running,
                                         availableDisplays: displays.map(\.uuid))
            WindowPlacer.apply(plan, displays: displays)
            Wallpaper.apply(name: config.contexts.first(where: { $0.id == contextID })?.wallpaper)
            activeID = contextID
            UserDefaults.standard.set(contextID, forKey: "activeContext")
            updateTitle()
        } catch {
            NSSound.beep()
            NSLog("DNZ-Scenes: switch failed: %@", String(describing: error))
        }
    }

    @objc private func pickContext(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { switchTo(id) }
    }

    // MARK: - editing

    private func role(forRunning bundleID: String) -> String {
        let displays = Displays.current()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let frame = WindowPlacer.firstWindowFrame(pid: app.processIdentifier) {
            let center = CGPoint(x: frame.midX, y: primaryHeight - frame.midY)  // AX -> AppKit
            if let display = displays.first(where: { $0.screen.frame.contains(center) }),
               let role = config.displays.first(where: { $0.value == display.uuid })?.key {
                return role
            }
        }
        return ["left", "laptop", "right"].first(where: { config.displays[$0] != nil }) ?? "left"
    }

    @objc private func addApp(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? Payload else { return }
        config = config.addingApp(p.bundleID, role: role(forRunning: p.bundleID), toContext: p.contextID)
        saveConfig()
    }

    @objc private func captureInto(_ sender: NSMenuItem) {
        guard WindowPlacer.isTrusted(prompt: true), let id = sender.representedObject as? String else { return }
        var appsByRole: [String: [String]] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
            guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
                  WindowPlacer.firstWindowFrame(pid: app.processIdentifier) != nil else { continue }
            appsByRole[role(forRunning: bundle), default: []].append(bundle)
        }
        config = config.settingSlots(contextID: id, appsByRole: appsByRole)
        saveConfig()
    }

    @objc private func mapDisplays() {
        config.displays = Displays.roles(Displays.current())
        saveConfig()
    }

    @objc private func resetProfiles() {
        guard confirm("Reset all profiles to defaults?",
                      "This replaces all 8 profiles (names, colors, hotkeys, wallpapers, apps). Display mapping is kept.") else { return }
        config = Config.starter(displays: config.displays)
        activeID = nil
        UserDefaults.standard.removeObject(forKey: "activeContext")
        saveConfig()
        registerHotkeys()
        updateTitle()
    }

    @objc private func openEditor() {
        editorModel.replace(config: config)
        // Open on the active profile instead of whatever row was selected last time.
        if let active = activeID, config.contexts.contains(where: { $0.id == active }) {
            editorModel.selectedContextID = active
        }
        if editorWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: EditorView(model: editorModel)))
            window.title = "DNZ-Scenes Profiles"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 860, height: 560))
            window.center()
            editorWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        addProfileItems(to: menu)
        menu.addItem(.separator())

        // Quick add: the app you were using before opening the menu
        if let front = NSWorkspace.shared.frontmostApplication, front.activationPolicy == .regular,
           let bundle = front.bundleIdentifier, bundle != Bundle.main.bundleIdentifier {
            let item = NSMenuItem(title: "Add \(AppInfo.name(bundle)) To", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for context in config.contexts {
                let entry = NSMenuItem(title: context.displayName, action: #selector(addApp(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = Payload(context.id, bundle)
                entry.state = context.slots.contains(where: { $0.apps.contains(bundle) }) ? .on : .off
                submenu.addItem(entry)
            }
            item.submenu = submenu
            menu.addItem(item)
        }

        let capture = NSMenuItem(title: "Capture Current Layout Into", action: nil, keyEquivalent: "")
        let captureMenu = NSMenu()
        for context in config.contexts {
            let entry = NSMenuItem(title: context.displayName, action: #selector(captureInto(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = context.id
            captureMenu.addItem(entry)
        }
        capture.submenu = captureMenu
        menu.addItem(capture)

        addItem(to: menu, "Show Profile Ring", #selector(showRingAction))
        addItem(to: menu, "Edit Profiles...", #selector(openEditor), key: ",")
        menu.addItem(.separator())

        addItem(to: menu, "Map Displays to Current Screens", #selector(mapDisplays))
        addItem(to: menu, "Reset Profiles to Defaults...", #selector(resetProfiles))
        addItem(to: menu, "Reload Config", #selector(reloadConfig))
        addItem(to: menu, "Open Config Folder", #selector(openConfigFolder))
        menu.addItem(.separator())
        let trusted = WindowPlacer.isTrusted(prompt: false)
        addItem(to: menu, trusted ? "Accessibility: granted" : "Accessibility: not granted (open settings)",
                #selector(openAccessibilitySettings))
        menu.addItem(.separator())
        addItem(to: menu, "About DNZ-Scenes", #selector(showAbout))   // directly above Quit (about-standard.md §1)
        menu.addItem(NSMenuItem(title: "Quit DNZ-Scenes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// Header, then one row per profile: colored dot, name (bold when active, with a checkmark),
    /// and the shortcut drawn natively and right-aligned (e.g. ⌃⌥1).
    private func addProfileItems(to menu: NSMenu) {
        if #available(macOS 14.0, *) {
            menu.addItem(NSMenuItem.sectionHeader(title: "Profiles"))
        } else {
            let header = NSMenuItem(title: "PROFILES", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        for context in config.contexts {
            let isActive = context.id == activeID
            let item = NSMenuItem(title: context.displayName, action: #selector(pickContext(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = context.id
            item.state = isActive ? .on : .off
            item.image = Self.dot(ProfileColor.ns(context.colorHex))
            if isActive {
                item.attributedTitle = NSAttributedString(
                    string: context.displayName,
                    attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
            }
            if let text = context.hotkey, let spec = HotkeySpec.parse(text) {
                item.keyEquivalent = String(spec.key)
                var mask: NSEvent.ModifierFlags = []
                if spec.control { mask.insert(.control) }
                if spec.option { mask.insert(.option) }
                if spec.command { mask.insert(.command) }
                if spec.shift { mask.insert(.shift) }
                item.keyEquivalentModifierMask = mask
            }
            menu.addItem(item)
        }
    }

    private static func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }

    /// Standard DNZ About window (core/standards/about-standard.md); see AboutWindow.swift.
    @objc private func showAbout() {
        Task { @MainActor in AboutWindow.show() }
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    /// Template glyph (three stacked scenes) drawn in code so it follows light/dark menu bars.
    private static func menuBarGlyph() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let k: CGFloat = 0.75  // 24-unit design grid -> 18 pt
            func card(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, alpha: CGFloat, fill: Bool) {
                let path = NSBezierPath(roundedRect: NSRect(x: x * k, y: y * k, width: w * k, height: h * k),
                                        xRadius: 2 * k, yRadius: 2 * k)
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSColor.black.withAlphaComponent(alpha).setStroke()
                if fill { path.fill() } else { path.lineWidth = 1.5 * k; path.stroke() }
            }
            card(2.5, 2.5, 13, 9.5, alpha: 0.55, fill: false)
            card(5.5, 6.5, 13, 9.5, alpha: 0.8, fill: false)
            card(8.5, 10.5, 13, 10, alpha: 1, fill: true)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func updateTitle() {
        let active = config.contexts.first(where: { $0.id == activeID })
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "\u{25CF} ", attributes: [
            .foregroundColor: active.map { ProfileColor.ns($0.colorHex) } ?? NSColor.secondaryLabelColor
        ]))
        text.append(NSAttributedString(string: active?.displayName ?? "Scenes"))
        statusItem.button?.attributedTitle = text
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(ConfigStore.directory)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func confirm(_ title: String, _ message: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
