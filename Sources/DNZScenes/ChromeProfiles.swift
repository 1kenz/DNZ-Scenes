import AppKit
import ApplicationServices
import Foundation

/// Chrome profile discovery that needs no extra permission: names come from the titles of open
/// Chrome windows ("<page> - Google Chrome - <profile name>"), read through the Accessibility
/// permission the app already has. Chrome's own data folder is never read.
enum ChromeProfiles {
    struct Profile: Equatable {
        let name: String
    }

    // "<page> - Google Chrome - <profile>"; Chrome may use a hyphen, en dash or em dash.
    private static let pattern = try! NSRegularExpression(pattern: "\\s[-\u{2013}\u{2014}]\\s(?:Google Chrome|Chrome)\\s[-\u{2013}\u{2014}]\\s(.+)$")

    static func profileName(inTitle title: String) -> String? {
        let range = NSRange(title.startIndex..., in: title)
        guard let match = pattern.firstMatch(in: title, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: title) else { return nil }
        return String(title[r]).trimmingCharacters(in: .whitespaces)
    }

    /// Profiles that currently have at least one open window.
    static func all() -> [Profile] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else {
            writeDiagnostics(["Chrome is not running"])
            return []
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        guard status == .success, let windows = value as? [AXUIElement] else {
            writeDiagnostics(["Could not read Chrome windows (AX status \(status.rawValue)); is Accessibility granted?"])
            return []
        }
        var names = Set<String>()
        var titles: [String] = []
        for window in windows {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            let t = (title as? String) ?? ""
            titles.append(t)
            if let name = profileName(inTitle: t) { names.insert(name) }
        }
        if names.isEmpty { writeDiagnostics(["No profile name found in these window titles:"] + titles) }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { Profile(name: $0) }
    }

    static func profile(inTitle title: String, among names: [String]) -> String? {
        guard let found = profileName(inTitle: title) else { return nil }
        return names.first { $0 == found }
    }

    /// Written when no profile is detected, so the cause can be seen (menu: Open Config Folder).
    private static func writeDiagnostics(_ lines: [String]) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DNZ-Scenes/chrome-titles.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// A profile whose window is not open cannot be started without reading Chrome's data folder,
    /// so it is skipped; open that profile's window once and the next switch will place it.
    static func launch(name: String) {
        NSLog("DNZ-Scenes: Chrome profile '%@' has no open window; open it once in Chrome", name)
    }
}
