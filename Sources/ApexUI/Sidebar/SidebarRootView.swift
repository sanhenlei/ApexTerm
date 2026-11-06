import SwiftUI
import AppKit
import ApexCore

/// NSOpenPanel helper for choosing (and configuring) the library workdir.
enum LibraryWorkdirPicker {
    /// Presents a directory picker; on success remembers the sandbox bookmark and
    /// points `LibraryStore` at the chosen directory. Returns false when cancelled.
    @MainActor
    @discardableResult
    static func chooseAndConfigure(onError: ((String) -> Void)? = nil) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "快捷命令、笔记与会话配置将以文件形式保存在此目录。\n把它放进 iCloud Drive 或其他同步盘即可多设备同步。"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return configure(url: url, onError: onError)
    }

    @MainActor
    @discardableResult
    static func configure(url: URL, onError: ((String) -> Void)? = nil) -> Bool {
        if DistributionChannel.current == .appStore {
            try? FileAccessStore.shared.remember(url, isDirectory: true)
        }
        do {
            try LibraryStore.shared.configure(workdir: url, persist: true)
            return true
        } catch {
            onError?(error.localizedDescription)
            return false
        }
    }
}

/// Root of the sidebar: a three-section switcher (会话 / 快捷命令 / 笔记) with the
/// existing sessions tree kept intact as the first section.
public struct SidebarRootView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = LibraryStore.shared

    let store: SessionStore
    @Binding var selectedSession: Session?
    let onConnect: (Session) -> Void
    let onRunSnippet: ((Snippet) -> Void)?
    let onInsertCommand: (_ command: String, _ executeNow: Bool) -> Void
    let onOpenFile: (LibraryFile) -> Void

    @State private var isWorkdirOnboardingPresented = false

    public init(
        store: SessionStore,
        selectedSession: Binding<Session?>,
        onConnect: @escaping (Session) -> Void,
        onRunSnippet: ((Snippet) -> Void)? = nil,
        onInsertCommand: @escaping (_ command: String, _ executeNow: Bool) -> Void,
        onOpenFile: @escaping (LibraryFile) -> Void
    ) {
        self.store = store
        self._selectedSession = selectedSession
        self.onConnect = onConnect
        self.onRunSnippet = onRunSnippet
        self.onInsertCommand = onInsertCommand
        self.onOpenFile = onOpenFile
    }

    public var body: some View {
        VStack(spacing: 0) {
            sectionSwitcher

            Divider()
                .padding(.horizontal, ApexStyle.s4)

            switch settings.sidebarActiveSection {
            case .sessions:
                SidebarView(
                    store: store,
                    selectedSession: $selectedSession,
                    onConnect: onConnect,
                    onRunSnippet: onRunSnippet
                )
            case .commands:
                CommandLibraryView(onInsert: onInsertCommand, onOpenFile: onOpenFile)
            case .notes:
                NoteLibraryView(onOpenFile: onOpenFile)
            }
        }
        .onAppear {
            if settings.libraryWorkdirPath.isEmpty {
                isWorkdirOnboardingPresented = true
            } else {
                migrateSnippetsIfNeeded()
            }
        }
        .onChange(of: settings.libraryWorkdirPath) { _, newPath in
            guard !newPath.isEmpty else { return }
            migrateSnippetsIfNeeded()
            mirrorSessionsSnapshot()
        }
        .sheet(isPresented: $isWorkdirOnboardingPresented) {
            WorkdirOnboardingSheet()
                .apexTheme()
        }
    }

    // MARK: - Migration & Session Mirror

    /// One-time legacy migration: snippets.json entries become command files
    /// as soon as a workdir exists and no commands have been created yet.
    private func migrateSnippetsIfNeeded() {
        guard library.workdirURL != nil,
              library.commands.isEmpty,
              !store.snippets.isEmpty else { return }
        _ = try? library.migrateSnippets(from: store.snippets)
    }

    /// Seeds the workdir with a sessions.json snapshot right after configuration,
    /// so a synced folder is immediately usable on another machine.
    private func mirrorSessionsSnapshot() {
        guard let data = try? store.exportSessionsJSON() else { return }
        library.mirrorSessionsJSON(data)
    }

    private var sectionSwitcher: some View {
        HStack(spacing: ApexStyle.sCompact) {
            ApexPillButton(
                title: "会话",
                icon: "server.rack",
                isSelected: settings.sidebarActiveSection == .sessions,
                count: store.sessions.count
            ) {
                settings.sidebarActiveSection = .sessions
            }
            ApexPillButton(
                title: "快捷命令",
                icon: "terminal",
                isSelected: settings.sidebarActiveSection == .commands,
                count: library.commands.count
            ) {
                settings.sidebarActiveSection = .commands
            }
            ApexPillButton(
                title: "笔记",
                icon: "doc.text",
                isSelected: settings.sidebarActiveSection == .notes,
                count: library.notes.count
            ) {
                settings.sidebarActiveSection = .notes
            }
        }
        .padding(.horizontal, ApexStyle.s4)
        .padding(.vertical, ApexStyle.s3)
    }
}

/// One-time workdir setup shown on first launch until a directory is configured.
private struct WorkdirOnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: ApexStyle.s4) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            VStack(spacing: ApexStyle.s2) {
                Text("选择工作目录")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(ApexStyle.primary)

                Text("快捷命令、笔记与会话配置将以文件形式保存在此目录。\n把它放进 iCloud Drive 或其他同步盘，即可在多台电脑间同步。")
                    .font(.subheadline)
                    .foregroundStyle(ApexStyle.secondary)
                    .multilineTextAlignment(.center)

                Text("commands/ · notes/ · sessions.json")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ApexStyle.subtleSurface, in: RoundedRectangle(cornerRadius: ApexStyle.badgeRadius))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(ApexStyle.error)
            }

            HStack(spacing: ApexStyle.s2) {
                ApexActionButton("稍后再说", tint: ApexStyle.secondary, size: .regular) {
                    dismiss()
                }
                ApexActionButton(
                    "使用默认目录",
                    icon: "house",
                    tint: ApexStyle.secondary,
                    size: .regular
                ) {
                    configureDefault()
                }
                ApexActionButton(
                    "选择目录…",
                    icon: "folder",
                    tint: ApexStyle.accent,
                    size: .regular,
                    isProminent: true
                ) {
                    chooseDirectory()
                }
            }
        }
        .padding(ApexStyle.s6)
        .frame(width: 480)
    }

    private func configureDefault() {
        let path = AppSettings.defaultLibraryWorkdirPath
        guard !path.isEmpty else {
            errorMessage = "无法定位默认目录"
            return
        }
        let configured = LibraryWorkdirPicker.configure(url: URL(fileURLWithPath: path, isDirectory: true)) { error in
            errorMessage = error
        }
        if configured {
            dismiss()
        }
    }

    private func chooseDirectory() {
        let configured = LibraryWorkdirPicker.chooseAndConfigure { error in
            errorMessage = error
        }
        if configured {
            dismiss()
        }
    }
}
