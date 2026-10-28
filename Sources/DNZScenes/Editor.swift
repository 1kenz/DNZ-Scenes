import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import ScenesCore

// MARK: - helpers

enum ProfileColor {
    static func ns(_ hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return .systemGray }
        return NSColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func hex(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "#8A8A8A" }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

enum AppInfo {
    static func name(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    static func icon(_ bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}

// MARK: - model

final class EditorModel: ObservableObject {
    @Published var config: Config
    @Published var selectedContextID: String?
    var onChange: (Config) -> Void = { _ in }
    var roleForApp: (String) -> String = { _ in "left" }

    init(config: Config) {
        self.config = config
        self.selectedContextID = config.contexts.first?.id
    }

    /// Edit made in the editor: publish, then let the app save it.
    func apply(_ newConfig: Config) {
        config = newConfig
        onChange(newConfig)
    }

    /// Config changed elsewhere (menu, reload): refresh without calling onChange.
    func replace(config newConfig: Config) {
        config = newConfig
        if !newConfig.contexts.contains(where: { $0.id == selectedContextID }) {
            selectedContextID = newConfig.contexts.first?.id
        }
    }

    func addProfile() {
        guard let result = config.addingContext(name: "New Profile") else {
            NSSound.beep()
            return
        }
        apply(result.config)
        selectedContextID = result.id
    }

    func removeProfile(_ contextID: String) {
        let updated = config.removingContext(contextID)
        guard updated.contexts.count < config.contexts.count else { return }
        let oldIndex = config.contexts.firstIndex { $0.id == contextID } ?? 0
        apply(updated)
        selectedContextID = updated.contexts[min(oldIndex, updated.contexts.count - 1)].id
    }

    func addApps(_ bundleIDs: [String], to contextID: String) {
        var updated = config
        for id in bundleIDs {
            updated = updated.addingApp(id, role: roleForApp(id), toContext: contextID)
        }
        apply(updated)
    }

    func removeApps(_ bundleIDs: Set<String>, from contextID: String) {
        var updated = config
        for id in bundleIDs { updated = updated.removingApp(id, fromContext: contextID) }
        apply(updated)
    }

    func moveApps(_ bundleIDs: Set<String>, to role: String, in contextID: String) {
        var updated = config
        for id in bundleIDs { updated = updated.addingApp(id, role: role, toContext: contextID) }
        apply(updated)
    }
}

// MARK: - views

private struct AppEntry: Identifiable {
    let id: String   // bundle identifier
    let name: String
}

private struct AppRow: Identifiable {
    let id: String   // bundle identifier
    let role: String
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @State private var selectedApps = Set<String>()
    @State private var showRunningPicker = false
    @State private var showDeleteConfirm = false

    private let roles = ["left", "right", "laptop"]

    private var current: Context? {
        model.config.contexts.first { $0.id == model.selectedContextID }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(model.config.contexts, id: \.id, selection: $model.selectedContextID) { context in
                    HStack {
                        Circle().fill(Color(nsColor: ProfileColor.ns(context.colorHex))).frame(width: 10, height: 10)
                        Text(context.displayName)
                    }
                }
                Divider()
                HStack {
                    Button { model.addProfile() } label: { Image(systemName: "plus") }
                        .help("Add profile")
                        .disabled(model.config.contexts.count >= Config.maxContexts)
                    Button { showDeleteConfirm = true } label: { Image(systemName: "minus") }
                        .help("Delete selected profile")
                        .disabled(current == nil || model.config.contexts.count <= 1)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 200)
            Divider()
            if let context = current {
                detail(context)
            } else {
                Text("Select a profile").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 780, minHeight: 480)
        .onChange(of: model.selectedContextID) { _ in selectedApps = [] }
        .confirmationDialog("Delete profile \"\(current?.displayName ?? "")\"?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = model.selectedContextID { model.removeProfile(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its app list, wallpaper choice and hotkey are removed. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func detail(_ context: Context) -> some View {
        let id = context.id
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Name").frame(width: 80, alignment: .leading)
                TextField("Name", text: nameBinding(id))
                ColorPicker("", selection: colorBinding(id)).labelsHidden()
            }

            HStack(alignment: .top) {
                Text("Wallpaper").frame(width: 80, alignment: .leading)
                WallpaperThumb(name: context.wallpaper)
                VStack(alignment: .leading, spacing: 6) {
                    Button("Choose Image...") { chooseWallpaper(id) }
                    Button("Remove Wallpaper") {
                        model.apply(model.config.settingWallpaper(id, name: nil))
                    }
                    .disabled(context.wallpaper == nil)
                    Text(context.wallpaper ?? "none").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()
            Text("Apps (select several with Shift or Cmd)").font(.headline)

            List(selection: $selectedApps) {
                ForEach(rows(context)) { row in
                    HStack {
                        Image(nsImage: AppInfo.icon(row.id)).resizable().frame(width: 18, height: 18)
                        Text(AppInfo.name(row.id))
                        Spacer()
                        Text(row.role).foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                Button("Add Running Apps...") { showRunningPicker = true }
                Button("Add From Applications...") { chooseApplications(id) }
                Spacer()
                Menu("Move Selected To") {
                    ForEach(roles, id: \.self) { role in
                        Button(role) { model.moveApps(selectedApps, to: role, in: id) }
                    }
                }
                .disabled(selectedApps.isEmpty)
                Button("Remove Selected (\(selectedApps.count))") {
                    model.removeApps(selectedApps, from: id)
                    selectedApps = []
                }
                .disabled(selectedApps.isEmpty)
            }
        }
        .padding()
        .sheet(isPresented: $showRunningPicker) {
            RunningAppsPicker(already: Set(context.slots.flatMap(\.apps))) { ids in
                model.addApps(ids, to: id)
            }
        }
    }

    private func rows(_ context: Context) -> [AppRow] {
        context.slots.flatMap { slot in slot.apps.map { AppRow(id: $0, role: slot.displayRole) } }
    }

    private func nameBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { model.config.contexts.first { $0.id == id }?.name ?? "" },
            set: { model.apply(model.config.renamingContext(id, to: $0)) })
    }

    private func colorBinding(_ id: String) -> Binding<Color> {
        Binding(
            get: {
                Color(nsColor: ProfileColor.ns(model.config.contexts.first { $0.id == id }?.colorHex ?? "#8A8A8A"))
            },
            set: { model.apply(model.config.settingColor(id, hex: ProfileColor.hex($0))) })
    }

    private func chooseWallpaper(_ id: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a wallpaper for this profile"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let folder = ConfigStore.directory.appendingPathComponent("wallpapers", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
            let name = "custom-\(id)-\(UUID().uuidString.prefix(8)).\(ext)"
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
            model.apply(model.config.settingWallpaper(id, name: name))
        } catch {
            NSLog("DNZ-Scenes: could not import wallpaper: %@", String(describing: error))
            NSSound.beep()
        }
    }

    private func chooseApplications(_ id: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose one or more apps"
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        if !ids.isEmpty { model.addApps(ids, to: id) }
    }
}

private struct WallpaperThumb: View {
    let name: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.2))
            }
        }
        .frame(width: 160, height: 90)
        .clipped()
        .cornerRadius(6)
        .onAppear(perform: load)
        .onChange(of: name) { _ in load() }
    }

    private func load() {
        guard let name, let url = Wallpaper.url(for: name) else {
            image = nil
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let thumb = Self.thumbnail(url)
            DispatchQueue.main.async { image = thumb }
        }
    }

    private static func thumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}

private struct RunningAppsPicker: View {
    let already: Set<String>
    let onAdd: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<String>()

    private var apps: [AppEntry] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app -> AppEntry? in
                guard let id = app.bundleIdentifier else { return nil }
                return AppEntry(id: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select the apps to add").font(.headline)
            List(apps, selection: $selection) { app in
                HStack {
                    Image(nsImage: AppInfo.icon(app.id)).resizable().frame(width: 18, height: 18)
                    Text(app.name)
                    if already.contains(app.id) {
                        Spacer()
                        Text("already in profile").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add \(selection.count)") {
                    onAdd(Array(selection))
                    dismiss()
                }
                .disabled(selection.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 440)
    }
}
