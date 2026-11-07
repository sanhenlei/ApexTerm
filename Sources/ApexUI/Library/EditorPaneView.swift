import SwiftUI
import ApexCore

/// Right-side editor pane hosting library file tabs (quick commands + notes).
/// Save writes through `LibraryStore` (rename on title change, atomic content write).
struct EditorPaneView: View {
    @Binding var tabs: [EditorTabItem]
    @Binding var selectedTabId: UUID?
    let onInsertCommand: (_ command: String, _ executeNow: Bool) -> Void

    @ObservedObject private var library = LibraryStore.shared
    /// Shares the workspace visibility key so closing the last tab auto-hides the pane.
    @AppStorage("workspace.editorVisible") private var isEditorVisible = true

    @State private var tabPendingClose: EditorTabItem?

    private var currentTab: EditorTabItem? {
        tabs.first(where: { $0.id == selectedTabId }) ?? tabs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            if let tab = currentTab {
                content(for: tab)
            } else {
                emptyState
            }

            // Hidden ⌘S: saves the selected editor tab when the main window is key.
            Button("保存") {
                if let tab = currentTab {
                    saveTab(tab)
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .background(ApexStyle.surface)
        .confirmationDialog("有未保存的修改", isPresented: Binding(
            get: { tabPendingClose != nil },
            set: { if !$0 { tabPendingClose = nil } }
        )) {
            Button("放弃更改并关闭", role: .destructive) {
                if let tab = tabPendingClose {
                    removeTab(tab)
                }
                tabPendingClose = nil
            }
            Button("取消", role: .cancel) {
                tabPendingClose = nil
            }
        } message: {
            Text("「\(tabPendingClose?.title ?? "")」尚未保存的更改将丢失。")
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            EditorTabButton(
                                tab: tab,
                                isSelected: tab.id == currentTab?.id,
                                onSelect: { selectedTabId = tab.id },
                                onClose: { closeTab(tab) },
                                onCloseOthers: { closeOtherTabs(tab) }
                            )
                            .id(tab.id)
                        }
                    }
                    .padding(.horizontal, ApexStyle.s3)
                    .padding(.vertical, 4)
                }
                .onChange(of: selectedTabId) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(ApexStyle.hoverTransition) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onChange(of: tabs.count) { _, _ in
                    guard let selected = selectedTabId else { return }
                    proxy.scrollTo(selected, anchor: .center)
                }
            }

            ApexIconButton(
                icon: "xmark",
                label: "隐藏编辑器 (⌘⇧E)",
                size: 22,
                iconSize: 9
            ) {
                withAnimation(ApexStyle.hoverTransition) {
                    isEditorVisible = false
                }
            }
            .padding(.trailing, ApexStyle.s3)
        }
        .frame(height: 34)
        .background(ApexStyle.subtleSurface.opacity(0.55))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.squares.left")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("在左侧点击快捷命令或笔记\n即可在此查看和编辑")
                .font(.subheadline)
                .foregroundStyle(ApexStyle.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for tab: EditorTabItem) -> some View {
        switch tab.kind {
        case .command:
            CommandFileEditorView(
                tab: tab,
                onSave: { saveTab(tab) },
                onInsertCommand: onInsertCommand
            )
        case .note:
            NoteFileEditorView(
                tab: tab,
                onSave: { saveTab(tab) }
            )
        }
    }

    // MARK: - Actions

    private func closeTab(_ tab: EditorTabItem) {
        if tab.isDirty {
            tabPendingClose = tab
        } else {
            removeTab(tab)
        }
    }

    private func closeOtherTabs(_ keep: EditorTabItem) {
        // Dirty tabs stay open so unsaved edits are never lost by a bulk action.
        tabs.removeAll { $0.id != keep.id && !$0.isDirty }
        selectedTabId = keep.id
    }

    private func removeTab(_ tab: EditorTabItem) {
        tabs.removeAll { $0.id == tab.id }
        if selectedTabId == tab.id {
            selectedTabId = tabs.first?.id
        }
        if tabs.isEmpty {
            withAnimation(ApexStyle.hoverTransition) {
                isEditorVisible = false
            }
        }
    }

    private func saveTab(_ tab: EditorTabItem) {
        guard tab.isDirty, !tab.isSaving else { return }
        tab.isSaving = true
        defer { tab.isSaving = false }
        do {
            if tab.title != tab.initialTitle {
                let file = LibraryFile(url: tab.url, kind: tab.kind, title: tab.initialTitle, group: tab.group)
                let renamed = try library.rename(file, toTitle: tab.title)
                tab.url = renamed.url
                tab.group = renamed.group
                tab.title = renamed.title
            }
            let file = LibraryFile(url: tab.url, kind: tab.kind, title: tab.title, group: tab.group)
            try library.write(file, content: tab.content)
            tab.initialTitle = tab.title
            tab.initialContent = tab.content
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            tab.savedNotice = "已保存 \(formatter.string(from: Date()))"
        } catch {
            tab.lastError = error.localizedDescription
        }
    }
}

/// Lightweight tab chip for the editor pane with dirty dot and hover close.
struct EditorTabButton: View {
    @ObservedObject var tab: EditorTabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.kind == .command ? "terminal.fill" : "doc.text.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isSelected ? ApexStyle.accent : ApexStyle.secondary)

            Text(tab.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundColor(ApexStyle.primary)
                .lineLimit(1)

            if tab.isSaving {
                ProgressView()
                    .controlSize(.mini)
            } else if tab.isDirty {
                Circle()
                    .fill(ApexStyle.warning)
                    .frame(width: 5, height: 5)
            }

            ApexIconButton(
                icon: "xmark",
                label: "关闭 \(tab.title)",
                size: 16,
                iconSize: 7
            ) {
                onClose()
            }
            .opacity(isHovered ? 1.0 : 0.0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? ApexStyle.surface : (isHovered ? ApexStyle.primary.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? ApexStyle.border : Color.clear, lineWidth: 0.75)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(ApexStyle.hoverTransition) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("关闭") { onClose() }
            Button("关闭其他标签页") { onCloseOthers() }
        }
    }
}
