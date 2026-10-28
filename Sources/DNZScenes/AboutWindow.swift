// AboutWindow.swift — DNZ standard About window (frozen design v1.0)
// Project copy of core/templates/about/AboutWindow.swift.template (unchanged). DNZ-Scenes has no Localizable.strings, so English is shown.
//
// Spec:   core/standards/about-standard.md      Design: core/design/about/final/design-v1.0.html
// Use:    copy to the app target as AboutWindow.swift, then call `AboutWindow.show()` from the
//         "About <App>" menu item. Requires macOS 13+, AppKit + SwiftUI, no dependencies.
// Data:   Resources/app-info.json (static identity) + Info.plist (CFBundleShortVersionString,
//         CFBundleVersion) + keys written by the build script: DNZCommit, DNZReleaseDate,
//         DNZChannel, DNZEnvironment (see about-standard.md §3).
// i18n:   Strings use their English text as the key (`t("Details")`, always a string literal so key-parity
//         checks can find it). If the app has Localizable.strings, add every key used here to each language
//         file; without them English is shown. Apps with their own localization helper replace `t` by it.
// Rules:  no network access, no personal data, only https:/mailto: links (about-standard.md §4).

import AppKit
import SwiftUI

private func t(_ key: String) -> String { NSLocalizedString(key, value: key, comment: "") }

// MARK: - Data

struct AboutInfo {
    var name: String
    var purpose: String
    var developer: String
    var usesAI: Bool
    var version: String
    var build: String
    var commit: String
    var releaseDate: String   // YYYY-MM-DD (UTC) or "unknown"
    var channel: String       // stable | beta | dev
    var environment: String   // production | staging | development
    var links: [(title: String, url: URL)]

    static func load(bundle: Bundle = .main) -> AboutInfo {
        let plist = bundle.infoDictionary ?? [:]
        var json: [String: Any] = [:]
        if let url = bundle.url(forResource: "app-info", withExtension: "json") {
            if let data = try? Data(contentsOf: url),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = object
            } else {
                assertionFailure("app-info.json exists but is not valid JSON")   // build defect; debug builds only
            }
        }

        let fallbackName = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? "App"
        let purposes = json["purpose"] as? [String: String] ?? [:]
        let language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        let linkObject = json["links"] as? [String: String] ?? [:]

        func link(_ key: String, _ title: String) -> (title: String, url: URL)? {
            guard let raw = linkObject[key], !raw.isEmpty, let url = URL(string: raw),
                  ["https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return (title, url)
        }

        return AboutInfo(
            name: (json["name"] as? String) ?? fallbackName,
            purpose: purposes[language] ?? purposes["en"] ?? "",
            developer: (json["developer"] as? String) ?? "DNZ Security & Software",
            usesAI: (json["usesAI"] as? Bool) ?? false,
            version: (plist["CFBundleShortVersionString"] as? String) ?? "dev",
            build: (plist["CFBundleVersion"] as? String) ?? "0",
            commit: (plist["DNZCommit"] as? String) ?? "unknown",
            releaseDate: (plist["DNZReleaseDate"] as? String) ?? "unknown",
            channel: (plist["DNZChannel"] as? String) ?? "dev",
            environment: (plist["DNZEnvironment"] as? String) ?? "development",
            links: [link("privacy", t("Privacy")), link("licenses", t("Licenses")),
                    link("releaseNotes", t("Release notes")), link("support", t("Support"))].compactMap { $0 }
        )
    }

    /// English, one line, no personal data or paths — for support tickets.
    var copyText: String {
        let channelEN = ["stable": "Stable", "beta": "Beta", "dev": "Development"][channel] ?? channel
        let envEN = ["production": "Production", "staging": "Staging", "development": "Development"][environment] ?? environment
        return "\(name) \(version) (build \(build)) · commit \(commit) · \(channelEN) · \(envEN) · \(releaseDate)"
    }

    var channelDisplay: String { ["stable": t("Stable"), "beta": t("Beta"), "dev": t("Development")][channel] ?? channel }
    var environmentDisplay: String {
        ["production": t("Production"), "staging": t("Staging"), "development": t("Development")][environment] ?? environment
    }
    var releasedDisplay: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: releaseDate) else { return releaseDate }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    var copyrightYear: String { releaseDate.count >= 4 && releaseDate.first?.isNumber == true ? String(releaseDate.prefix(4)) : String(Calendar.current.component(.year, from: Date())) }
}

// MARK: - View

private struct AboutView: View {
    let info: AboutInfo
    let onLayoutChange: () -> Void
    @State private var expanded = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            detailsBox
            if !info.links.isEmpty { linkRow }
            legal
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(info.name)
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 14)
            Text(String(format: t("Version %@ (%@)"), info.version, info.build))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            if !info.purpose.isEmpty {
                Text(info.purpose)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
                    .padding(.top, 14)
            }
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
    }

    private var detailsBox: some View {
        VStack(spacing: 0) {
            Button {
                if reduceMotion { expanded.toggle() } else { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
                onLayoutChange()
            } label: {
                HStack {
                    Text(t("Details")).fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? t("Expanded") : t("Collapsed"))

            if expanded {
                VStack(spacing: 8) {
                    row(t("Commit"), info.commit, mono: true)
                    row(t("Released"), info.releasedDisplay)
                    row(t("Channel"), info.channelDisplay)
                    row(t("Environment"), info.environmentDisplay)
                    row(t("Developer"), info.developer)
                    Button(copied ? t("Copied ✓") : t("Copy version info")) { copy() }
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal, 24)
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var linkRow: some View {
        HStack(spacing: 16) {
            ForEach(0..<info.links.count, id: \.self) { i in
                Link(info.links[i].title, destination: info.links[i].url)
            }
        }
        .font(.callout)
        .padding(.top, 22)
    }

    private var legal: some View {
        VStack(spacing: 2) {
            Text(String(format: t("© %@ %@. All rights reserved."), info.copyrightYear, info.developer))
            if info.usesAI { Text(t("This app includes AI-powered features.")) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 18)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info.copyText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

// MARK: - Window

private final class AboutPanel: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }   // Esc closes
}

@MainActor
enum AboutWindow {
    private static var window: NSWindow?
    private static var host: NSHostingController<AboutView>?

    static func show(bundle: Bundle = .main) {
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let info = AboutInfo.load(bundle: bundle)
        let controller = NSHostingController(rootView: AboutView(info: info, onLayoutChange: { resizeToFit() }))
        let w = AboutPanel(contentViewController: controller)
        w.title = String(format: t("About %@"), info.name)   // hidden visually, read by VoiceOver
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.setContentSize(controller.view.fittingSize)
        w.center()
        host = controller
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Re-fit the window height after the Details box expands or collapses (top edge stays put).
    private static func resizeToFit() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let w = window, let host else { return }
            let newSize = w.frameRect(forContentRect: NSRect(origin: .zero, size: host.view.fittingSize)).size
            var frame = w.frame
            frame.origin.y += frame.height - newSize.height
            frame.size = newSize
            w.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
    }
}
