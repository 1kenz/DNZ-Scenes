import AppKit

enum Wallpaper {
    /// Looks in ~/Library/Application Support/DNZ-Scenes/wallpapers first (user overrides),
    /// then in the app bundle's Resources/wallpapers.
    static func url(for name: String) -> URL? {
        // plain file names only; no path components from config
        guard name == (name as NSString).lastPathComponent, !name.isEmpty, !name.hasPrefix(".") else { return nil }
        let custom = ConfigStore.directory.appendingPathComponent("wallpapers").appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("wallpapers").appendingPathComponent(name),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return nil
    }

    static func apply(name: String?) {
        guard let name else { return }
        guard let url = url(for: name) else {
            NSLog("DNZ-Scenes: wallpaper not found: %@", name)
            return
        }
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                NSLog("DNZ-Scenes: could not set wallpaper: %@", String(describing: error))
            }
        }
    }
}
