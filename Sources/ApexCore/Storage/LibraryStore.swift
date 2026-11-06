import Foundation
import Darwin
import Combine

/// Errors thrown by `LibraryStore` operations.
public enum LibraryStoreError: LocalizedError, Equatable {
    case notConfigured
    case invalidName(String)
    case fileNotFound(URL)
    case targetExists(URL)
    case groupNotFound(String)
    case groupNotEmpty(String, Int)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未选择工作目录"
        case .invalidName(let name):
            return "无效的名称：\(name)"
        case .fileNotFound(let url):
            return "文件不存在：\(url.lastPathComponent)"
        case .targetExists(let url):
            return "已存在同名文件：\(url.deletingPathExtension().lastPathComponent)"
        case .groupNotFound(let name):
            return "分组不存在：\(name)"
        case .groupNotEmpty(let name, let count):
            return "分组「\(name)」内还有 \(count) 个文件"
        }
    }
}

/// Directory-level watcher posting a notification when the library folders change on disk.
/// Deliberately free of actor state so the DispatchSource event handler stays Sendable;
/// the store subscribes through Combine and rescans on the main run loop.
enum LibraryWorkdirWatcher {
    static let didChangeNotification = Notification.Name("ApexLibraryWorkdirDidChange")

    static func watch(directory: URL) -> DispatchSourceFileSystemObject? {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}

/// File-backed library of quick commands and Markdown notes under a user-chosen workdir.
///
/// Layout: `<workdir>/commands/<group>/<title>.sh` and `<workdir>/notes/<group>/<title>.md`.
/// The workdir is designed to live inside a synced folder (iCloud Drive, Dropbox, ...),
/// so groups are plain subdirectories, titles are plain filenames, and every mutation is
/// an atomic file operation another machine can pick up.
@MainActor
public final class LibraryStore: ObservableObject {
    public static let shared = LibraryStore()

    @Published public private(set) var commands: [LibraryFile] = []
    @Published public private(set) var notes: [LibraryFile] = []
    @Published public private(set) var commandGroups: [String] = []
    @Published public private(set) var noteGroups: [String] = []
    @Published public private(set) var workdirURL: URL?

    private let fileManager = FileManager.default
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var watcherCancellable: AnyCancellable?

    /// App singleton init: restores the previously configured workdir, if any.
    public init() {
        let path = AppSettings.shared.libraryWorkdirPath
        guard !path.isEmpty else { return }
        try? configure(workdir: URL(fileURLWithPath: path, isDirectory: true), persist: false)
    }

    /// Init for tests and previews with an explicit workdir. Settings are never touched.
    public init(workdir: URL) {
        try? configure(workdir: workdir, persist: false)
    }

    deinit {
        watchers.forEach { $0.cancel() }
    }

    // MARK: - Configuration

    /// Points the library at `workdir`, creating `commands/` and `notes/` when missing.
    /// When `persist` is true the path is stored in AppSettings so it survives relaunch.
    public func configure(workdir: URL, persist: Bool = true) throws {
        let standardized = workdir.standardizedFileURL
        try withLease(standardized) {
            for kind in [LibraryFileKind.command, .note] {
                try fileManager.createDirectory(
                    at: standardized.appendingPathComponent(kind.directoryName, isDirectory: true),
                    withIntermediateDirectories: true)
            }
        }
        workdirURL = standardized
        if persist {
            AppSettings.shared.libraryWorkdirPath = standardized.path
        }
        rescan()
        startWatching()
    }

    /// Detaches from the current workdir without touching any files.
    public func disconnect() {
        workdirURL = nil
        commands = []
        notes = []
        commandGroups = []
        noteGroups = []
        stopWatching()
        AppSettings.shared.libraryWorkdirPath = ""
    }

    // MARK: - Scanning

    /// Reloads files and groups from disk. Cheap by design: two flat directory levels.
    public func rescan() {
        guard let workdir = workdirURL else { return }
        commands = Self.scanFiles(kind: .command, in: workdir)
        notes = Self.scanFiles(kind: .note, in: workdir)
        commandGroups = Self.scanGroups(in: Self.rootDirectory(kind: .command, workdir: workdir))
        noteGroups = Self.scanGroups(in: Self.rootDirectory(kind: .note, workdir: workdir))
    }

    nonisolated static func rootDirectory(kind: LibraryFileKind, workdir: URL) -> URL {
        workdir.appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    /// Scans one level of group subdirectories plus their files, Finder-style ordering.
    nonisolated static func scanFiles(kind: LibraryFileKind, in workdir: URL) -> [LibraryFile] {
        let root = rootDirectory(kind: kind, workdir: workdir)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]) else {
            return []
        }
        let sorted = entries.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var files: [LibraryFile] = []
        for entry in sorted {
            let name = entry.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                let children = (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
                for child in children.sorted({ $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                    guard Self.isLibraryFile(child, kind: kind) else { continue }
                    files.append(LibraryFile(url: child, kind: kind, title: Self.title(of: child), group: name))
                }
            } else if Self.isLibraryFile(entry, kind: kind) {
                files.append(LibraryFile(url: entry, kind: kind, title: Self.title(of: entry), group: nil))
            }
        }
        return files
    }

    nonisolated static func scanGroups(in directory: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        return entries
            .filter { entry in
                !entry.lastPathComponent.hasPrefix(".")
                    && (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    nonisolated static func isLibraryFile(_ url: URL, kind: LibraryFileKind) -> Bool {
        guard !url.lastPathComponent.hasPrefix("."),
              url.pathExtension.lowercased() == kind.fileExtension,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
            return false
        }
        return true
    }

    nonisolated static func title(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    // MARK: - File CRUD

    @discardableResult
    public func createFile(kind: LibraryFileKind, title rawTitle: String, group: String? = nil, content: String = "") throws -> LibraryFile {
        guard let workdir = workdirURL else { throw LibraryStoreError.notConfigured }
        if let group {
            try ensureGroupDirectory(named: group, kind: kind, workdir: workdir)
        }
        let target = Self.uniqueURL(title: rawTitle, kind: kind, group: group, workdir: workdir)
        try withLease(target) {
            try Data(content.utf8).write(to: target, options: .atomic)
        }
        rescan()
        return LibraryFile(url: target, kind: kind, title: Self.title(of: target), group: group)
    }

    public func read(_ file: LibraryFile) throws -> String {
        guard fileManager.isReadableFile(atPath: file.url.path) else {
            throw LibraryStoreError.fileNotFound(file.url)
        }
        return try withLease(file.url) {
            try String(contentsOf: file.url, encoding: .utf8)
        }
    }

    /// Atomically overwrites the file content. External-change watchers pick it up.
    public func write(_ file: LibraryFile, content: String) throws {
        guard fileManager.fileExists(atPath: file.url.path) else {
            throw LibraryStoreError.fileNotFound(file.url)
        }
        try withLease(file.url) {
            try Data(content.utf8).write(to: file.url, options: .atomic)
        }
    }

    /// Renames the file so its filename-title stays in sync. Returns the updated entry.
    @discardableResult
    public func rename(_ file: LibraryFile, toTitle rawTitle: String) throws -> LibraryFile {
        let clean = Self.sanitizedTitle(rawTitle)
        guard !clean.isEmpty else { throw LibraryStoreError.invalidName(rawTitle) }
        let directory = file.url.deletingLastPathComponent()
        let target = directory.appendingPathComponent("\(clean).\(file.kind.fileExtension)")
        if target == file.url { return file }
        guard !fileManager.fileExists(atPath: target.path) else {
            throw LibraryStoreError.targetExists(target)
        }
        try withLease(target) {
            try fileManager.moveItem(at: file.url, to: target)
        }
        rescan()
        return LibraryFile(url: target, kind: file.kind, title: Self.title(of: target), group: file.group)
    }

    /// Moves a file into another group (nil = top level), deduplicating on collision.
    @discardableResult
    public func move(_ file: LibraryFile, toGroup group: String?) throws -> LibraryFile {
        guard let workdir = workdirURL else { throw LibraryStoreError.notConfigured }
        guard file.group != group else { return file }
        if let group {
            try ensureGroupDirectory(named: group, kind: file.kind, workdir: workdir)
        }
        let target = Self.uniqueURL(title: file.title, kind: file.kind, group: group, workdir: workdir)
        guard target != file.url else { return file }
        try withLease(target) {
            try fileManager.moveItem(at: file.url, to: target)
        }
        rescan()
        return LibraryFile(url: target, kind: file.kind, title: Self.title(of: target), group: group)
    }

    /// Deletes via Trash when available (recoverable), falling back to direct removal.
    public func delete(_ file: LibraryFile) throws {
        guard fileManager.fileExists(atPath: file.url.path) else {
            throw LibraryStoreError.fileNotFound(file.url)
        }
        try withLease(file.url) {
            do {
                try fileManager.trashItem(at: file.url, resultingItemURL: nil)
            } catch {
                try fileManager.removeItem(at: file.url)
            }
        }
        rescan()
    }

    // MARK: - Group Management

    @discardableResult
    public func createGroup(named rawName: String, kind: LibraryFileKind) throws -> String {
        guard let workdir = workdirURL else { throw LibraryStoreError.notConfigured }
        let name = Self.sanitizedTitle(rawName)
        let directory = Self.rootDirectory(kind: kind, workdir: workdir).appendingPathComponent(name, isDirectory: true)
        guard !fileManager.fileExists(atPath: directory.path) else { return name }
        try withLease(directory) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        rescan()
        return name
    }

    @discardableResult
    public func renameGroup(_ oldName: String, to rawName: String, kind: LibraryFileKind) throws -> String {
        guard let workdir = workdirURL else { throw LibraryStoreError.notConfigured }
        let newName = Self.sanitizedTitle(rawName)
        guard !newName.isEmpty else { throw LibraryStoreError.invalidName(rawName) }
        guard newName != oldName else { return oldName }
        let root = Self.rootDirectory(kind: kind, workdir: workdir)
        let oldDirectory = root.appendingPathComponent(oldName, isDirectory: true)
        guard fileManager.fileExists(atPath: oldDirectory.path) else {
            throw LibraryStoreError.groupNotFound(oldName)
        }
        let newDirectory = root.appendingPathComponent(newName, isDirectory: true)
        guard !fileManager.fileExists(atPath: newDirectory.path) else {
            throw LibraryStoreError.targetExists(newDirectory)
        }
        try withLease(newDirectory) {
            try fileManager.moveItem(at: oldDirectory, to: newDirectory)
        }
        rescan()
        return newName
    }

    /// Deletes a group directory. Non-empty groups require `includingFiles: true`;
    /// the file count is returned so callers can present a confirmation first.
    @discardableResult
    public func deleteGroup(_ name: String, kind: LibraryFileKind, includingFiles: Bool = false) throws -> Int {
        guard let workdir = workdirURL else { throw LibraryStoreError.notConfigured }
        let directory = Self.rootDirectory(kind: kind, workdir: workdir).appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw LibraryStoreError.groupNotFound(name)
        }
        let files = Self.scanFiles(kind: kind, in: workdir).filter { $0.group == name }
        if !files.isEmpty && !includingFiles {
            throw LibraryStoreError.groupNotEmpty(name, files.count)
        }
        try withLease(directory) {
            do {
                try fileManager.trashItem(at: directory, resultingItemURL: nil)
            } catch {
                try fileManager.removeItem(at: directory)
            }
        }
        rescan()
        return files.count
    }

    // MARK: - Migration & Session Mirror

    /// One-time migration of legacy `snippets.json` entries into command files.
    /// Returns the number of files created; a no-op when commands already exist.
    @discardableResult
    public func migrateSnippets(from snippets: [Snippet]) throws -> Int {
        guard workdirURL != nil else { throw LibraryStoreError.notConfigured }
        guard commands.isEmpty else { return 0 }
        var count = 0
        for snippet in snippets where !snippet.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try createFile(kind: .command, title: snippet.title, group: Self.legacyGroup(for: snippet.category), content: snippet.command)
            count += 1
        }
        return count
    }

    /// Maps a legacy snippet category to a group name (nil = top level).
    nonisolated static func legacyGroup(for category: String) -> String? {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "general" else { return nil }
        let sanitized = sanitizedTitle(trimmed)
        return sanitized.isEmpty ? nil : sanitized
    }

    /// Mirrors the sanitized sessions JSON into the workdir for cross-machine pickup.
    public func mirrorSessionsJSON(_ data: Data) {
        guard let workdir = workdirURL else { return }
        let target = workdir.appendingPathComponent("sessions.json")
        try? withLease(target) {
            try data.write(to: target, options: .atomic)
        }
    }

    // MARK: - Naming Helpers

    /// Strips path separators and other problematic characters from a title used as filename.
    nonisolated public static func sanitizedTitle(_ raw: String) -> String {
        var cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        return cleaned
    }

    /// Resolves a collision-free file URL for `title` inside `group`.
    nonisolated static func uniqueURL(title rawTitle: String, kind: LibraryFileKind, group: String?, workdir: URL) -> URL {
        let sanitized = sanitizedTitle(rawTitle)
        let base = sanitized.isEmpty ? "未命名" : sanitized
        let directory: URL
        if let group, !group.isEmpty {
            directory = rootDirectory(kind: kind, workdir: workdir).appendingPathComponent(group, isDirectory: true)
        } else {
            directory = rootDirectory(kind: kind, workdir: workdir)
        }
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent("\(base).\(kind.fileExtension)")
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index).\(kind.fileExtension)")
            index += 1
        }
        return candidate
    }

    private func ensureGroupDirectory(named group: String, kind: LibraryFileKind, workdir: URL) throws {
        let directory = Self.rootDirectory(kind: kind, workdir: workdir).appendingPathComponent(group, isDirectory: true)
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try withLease(directory) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Watching

    private func startWatching() {
        stopWatching()
        guard let workdir = workdirURL else { return }
        for kind in [LibraryFileKind.command, .note] {
            let directory = Self.rootDirectory(kind: kind, workdir: workdir)
            if let watcher = LibraryWorkdirWatcher.watch(directory: directory) {
                watchers.append(watcher)
            }
        }
        watcherCancellable = NotificationCenter.default.publisher(for: LibraryWorkdirWatcher.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.rescan() }
            }
    }

    private func stopWatching() {
        watchers.forEach { $0.cancel() }
        watchers.removeAll()
        watcherCancellable = nil
    }

    // MARK: - Sandbox Access

    /// Runs `body` under a security-scoped lease on App Store builds; direct builds pass through.
    private func withLease<T>(_ url: URL, _ body: () throws -> T) throws -> T {
        guard DistributionChannel.current == .appStore,
              let lease = try? FileAccessStore.shared.acquire(url) else {
            return try body()
        }
        defer { lease.close() }
        return try body()
    }
}
