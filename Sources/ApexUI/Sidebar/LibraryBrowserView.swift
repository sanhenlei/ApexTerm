import SwiftUI
import AppKit
import ApexCore

/// Generic file-backed library browser shared by the quick-command and note sidebar sections.
/// Groups are workdir subdirectories; dragging a row onto a group moves the underlying file.
struct LibraryBrowserView: View {
    @ObservedObject private var library = LibraryStore.shared

    let kind: LibraryFileKind
    /// nil for notes (primary click opens the editor); commands type into the terminal.
    let onInsert: ((_ command: String, _ executeNow: Bool) -> Void)?
    let onOpenFile: (LibraryFile) -> Void

    @State private var searchFilter = ""
    @State private var collapsedGroups: Set<String> = []
    @State private var toastMessage: String?

    @State private var fileToRename: LibraryFile?
    @State private var renameText = ""
    @State private var fileToDelete: LibraryFile?

    @State private var isGroupCreatePresented = false
    @State private var newGroupName = ""
    @State private var groupToRename: String?
    @State private var groupRenameText = ""
    @State private var groupToDelete: String?

    init(kind: LibraryFileKind,
         onInsert: ((_ command: String, _ executeNow: Bool) -> Void)? = nil,
         onOpenFile: @escaping (LibraryFile) -> Void) {
        self.kind = kind
        self.onInsert = onInsert
        self.onOpenFile = onOpenFile
    }

    private var isCommand: Bool { kind == .command }

    private var sectionTitle: String { isCommand ? "快捷命令" : "笔记" }

    private var files: [LibraryFile] { isCommand ? library.commands : library.notes }

    private var groups: [String] { isCommand ? library.commandGroups : library.noteGroups }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(sectionTitle)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(ApexStyle.primary)
                Spacer()
                Text("\(files.count) \(isCommand ? "条" : "篇")")
                    .font(.caption)
                    .foregroundStyle(ApexStyle.secondary)
            }
            .padding(.horizontal, ApexStyle.s4)
            .padding(.top, ApexStyle.s3)
            .padding(.bottom, ApexStyle.sRow)

            HStack(spacing: ApexStyle.sCompact) {
                TextField(L10n.searchPlaceholder, text: $searchFilter)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.searchPlaceholder)

                ApexIconButton(
                    icon: "folder.badge.plus",
                    label: "新建分组",
                    size: 24,
                    iconSize: 11
                ) {
                    newGroupName = ""
                    isGroupCreatePresented = true
                }

                ApexIconButton(
                    icon: "plus",
                    label: isCommand ? "新建快捷命令" : "新建笔记",
                    size: 24,
                    iconSize: 11,
                    isSelected: true
                ) {
                    createFile()
                }
            }
            .padding(.horizontal, ApexStyle.s4)
            .padding(.bottom, ApexStyle.s3)

            Divider()
                .padding(.horizontal, ApexStyle.s4)
                .padding(.bottom, ApexStyle.s1)

            if library.workdirURL == nil {
                LibraryWorkdirEmptyState {
                    LibraryWorkdirPicker.chooseAndConfigure { error in
                        showToast(error)
                    }
                }
            } else if files.isEmpty {
                emptyState
            } else {
                libraryList
            }
        }
        .alert("重命名\(isCommand ? "快捷命令" : "笔记")", isPresented: Binding(
            get: { fileToRename != nil },
            set: { if !$0 { fileToRename = nil } }
        )) {
            TextField("名称", text: $renameText)
            Button("确定") { performFileRename() }
            Button("取消", role: .cancel) {}
        }
        .alert("新建分组", isPresented: $isGroupCreatePresented) {
            TextField("分组名称", text: $newGroupName)
            Button("确定") { performGroupCreate() }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名分组", isPresented: Binding(
            get: { groupToRename != nil },
            set: { if !$0 { groupToRename = nil } }
        )) {
            TextField("分组名称", text: $groupRenameText)
            Button("确定") { performGroupRename() }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除「\(fileToDelete?.title ?? "")」？", isPresented: Binding(
            get: { fileToDelete != nil },
            set: { if !$0 { fileToDelete = nil } }
        )) {
            Button("删除 \(fileToDelete?.title ?? "")", role: .destructive) { performFileDelete() }
        } message: {
            Text("文件会移到废纸篓，可从访达恢复。")
        }
        .confirmationDialog("删除分组「\(groupToDelete ?? "")」？", isPresented: Binding(
            get: { groupToDelete != nil },
            set: { if !$0 { groupToDelete = nil } }
        )) {
            Button("删除分组与全部内容", role: .destructive) { performGroupDelete() }
        } message: {
            Text("分组内文件会一并移到废纸篓。")
        }
        .overlay(alignment: .bottom) {
            LibraryToastOverlay(message: toastMessage)
        }
    }

    // MARK: - List

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: isCommand ? "terminal" : "doc.text")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text(isCommand ? "还没有快捷命令" : "还没有笔记")
                    .font(.headline)
                    .foregroundColor(ApexStyle.primary)
                Text(isCommand ? "点击右上角 + 新建，或直接把现有文件放入工作目录。" : "点击右上角 + 新建笔记，支持 Markdown。")
                    .font(.subheadline)
                    .foregroundStyle(ApexStyle.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            ApexActionButton(
                isCommand ? "新建快捷命令" : "新建笔记",
                icon: "plus",
                tint: ApexStyle.accent,
                size: .regular,
                isProminent: true
            ) {
                createFile()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var libraryList: some View {
        List {
            Section(header: Label("未分组", systemImage: "tray.full").font(.caption).fontWeight(.semibold)) {
                ForEach(topLevelFiles) { file in
                    row(for: file)
                }
            }

            ForEach(visibleGroups, id: \.self) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { !collapsedGroups.contains(group) || !searchFilter.isEmpty },
                        set: { expanded in
                            if expanded { collapsedGroups.remove(group) }
                            else { collapsedGroups.insert(group) }
                        }
                    ),
                    content: {
                        ForEach(files(in: group)) { file in
                            row(for: file)
                        }
                    },
                    label: {
                        LibraryGroupLabel(
                            name: group,
                            count: files(in: group).count,
                            createLabel: isCommand ? "在此分组新建命令" : "在此分组新建笔记",
                            onCreate: { createFile(in: group) },
                            onRename: {
                                groupRenameText = group
                                groupToRename = group
                            },
                            onDelete: { groupToDelete = group }
                        )
                        .dropDestination(for: String.self) { items, _ in
                            handleDrop(items, toGroup: group)
                        }
                    }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 22)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, toGroup: nil)
        }
    }

    @ViewBuilder
    private func row(for file: LibraryFile) -> some View {
        LibraryFileRow(
            file: file,
            icon: isCommand ? "terminal.fill" : "doc.text.fill",
            iconColor: isCommand ? ApexStyle.accent : ApexStyle.secondary,
            primaryActionLabel: isCommand ? "双击打开命令文件" : "双击打开笔记",
            showsExecuteHint: isCommand,
            showsFillButton: isCommand,
            onFill: isCommand ? { executeNow in
                guard let onInsert else { return }
                guard let content = try? library.read(file), !content.isEmpty else {
                    showToast("命令内容为空")
                    return
                }
                onInsert(content, executeNow)
            } : nil,
            onOpen: { onOpenFile(file) }
        )
        .draggable(file.url.absoluteString)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .contextMenu {
            if isCommand, let onInsert {
                Button("输入到当前会话") {
                    if let content = try? library.read(file) {
                        onInsert(content, false)
                    }
                }
                Button("立即执行") {
                    if let content = try? library.read(file) {
                        onInsert(content, true)
                    }
                }
                Divider()
            }
            Button("编辑") { onOpenFile(file) }
            Button("重命名") {
                renameText = file.title
                fileToRename = file
            }
            moveMenu(for: file)
            Divider()
            Button("删除", role: .destructive) { fileToDelete = file }
        }
    }

    @ViewBuilder
    private func moveMenu(for file: LibraryFile) -> some View {
        Menu("移动到分组") {
            Button("未分组") {
                move(file, toGroup: nil)
            }
            ForEach(groups, id: \.self) { group in
                Button(group) {
                    move(file, toGroup: group)
                }
            }
        }
    }

    // MARK: - Data Helpers

    private var filteredFiles: [LibraryFile] {
        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return files }
        return files.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var topLevelFiles: [LibraryFile] {
        filteredFiles.filter { $0.group == nil }
    }

    private func files(in group: String) -> [LibraryFile] {
        filteredFiles.filter { $0.group == group }
    }

    private var visibleGroups: [String] {
        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return groups }
        return groups.filter { !files(in: $0).isEmpty }
    }

    // MARK: - Actions

    /// Creates a command/note file (in `group` when provided) and opens it in the editor pane.
    private func createFile(in group: String? = nil) {
        do {
            let defaultContent = isCommand ? "" : "# 新笔记\n"
            let file = try library.createFile(
                kind: kind,
                title: isCommand ? "新命令" : "新笔记",
                group: group,
                content: defaultContent
            )
            onOpenFile(file)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func performFileRename() {
        guard let file = fileToRename else { return }
        do {
            _ = try library.rename(file, toTitle: renameText)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func performFileDelete() {
        guard let file = fileToDelete else { return }
        do {
            try library.delete(file)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func performGroupCreate() {
        do {
            _ = try library.createGroup(named: newGroupName, kind: kind)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func performGroupRename() {
        guard let group = groupToRename else { return }
        do {
            _ = try library.renameGroup(group, to: groupRenameText, kind: kind)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func performGroupDelete() {
        guard let group = groupToDelete else { return }
        do {
            _ = try library.deleteGroup(group, kind: kind, includingFiles: true)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func move(_ file: LibraryFile, toGroup group: String?) {
        do {
            _ = try library.move(file, toGroup: group)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func handleDrop(_ items: [String], toGroup group: String?) -> Bool {
        guard let first = items.first,
              let url = URL(string: first),
              let file = files.first(where: { $0.url == url }),
              file.group != group else { return false }
        do {
            _ = try library.move(file, toGroup: group)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    private func showToast(_ message: String) {
        withAnimation(ApexStyle.hoverTransition) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if toastMessage == message {
                withAnimation(.easeOut(duration: 0.2)) {
                    toastMessage = nil
                }
            }
        }
    }
}

/// Sidebar section for file-backed quick commands. Single click types the command
/// into the active terminal without executing; ⌥-click types and runs it.
public struct CommandLibraryView: View {
    let onInsert: (_ command: String, _ executeNow: Bool) -> Void
    let onOpenFile: (LibraryFile) -> Void

    public init(
        onInsert: @escaping (_ command: String, _ executeNow: Bool) -> Void,
        onOpenFile: @escaping (LibraryFile) -> Void
    ) {
        self.onInsert = onInsert
        self.onOpenFile = onOpenFile
    }

    public var body: some View {
        LibraryBrowserView(kind: .command, onInsert: onInsert, onOpenFile: onOpenFile)
    }
}

/// Sidebar section for Markdown notes. Click opens the note in the editor pane.
public struct NoteLibraryView: View {
    let onOpenFile: (LibraryFile) -> Void

    public init(onOpenFile: @escaping (LibraryFile) -> Void) {
        self.onOpenFile = onOpenFile
    }

    public var body: some View {
        LibraryBrowserView(kind: .note, onOpenFile: onOpenFile)
    }
}
