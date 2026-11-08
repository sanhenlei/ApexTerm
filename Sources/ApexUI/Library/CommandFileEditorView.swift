import SwiftUI
import AppKit
import ApexCore

/// Editor for a quick-command file: title field (renames the file on save) plus a
/// monospaced command editor. Insert types into the terminal without executing;
/// Run types and presses Enter.
struct CommandFileEditorView: View {
    @ObservedObject var tab: EditorTabItem
    let onSave: () -> Void
    let onInsertCommand: (_ command: String, _ executeNow: Bool) -> Void

    @ObservedObject private var themeSettings = AppSettings.shared
    @State private var showsFindBar = false

    private var editorPalette: NativeCodeEditor.EditorPalette? {
        guard !themeSettings.followsSystemAppearance else { return nil }
        return NativeCodeEditor.EditorPalette(
            background: NSColor(ApexStyle.surface),
            text: NSColor(ApexStyle.primary),
            gutter: NSColor(ApexStyle.subtleSurface),
            gutterText: NSColor(ApexStyle.secondary),
            selection: NSColor(ApexStyle.selection)
        )
    }

    private var lineCount: Int {
        tab.content.isEmpty ? 0 : tab.content.components(separatedBy: .newlines).count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ApexStyle.s2) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundColor(ApexStyle.accent)

                TextField("标题", text: $tab.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .semibold))
                    .help("标题即文件名，保存时重命名文件")

                if tab.isSaving {
                    ProgressView()
                        .controlSize(.mini)
                } else if tab.isDirty {
                    Circle()
                        .fill(ApexStyle.warning)
                        .frame(width: 6, height: 6)
                        .help("有未保存的修改")
                }

                if let notice = tab.savedNotice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundColor(ApexStyle.secondary)
                        .lineLimit(1)
                }
                if let error = tab.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(ApexStyle.error)
                        .lineLimit(1)
                        .help(error)
                }

                Spacer(minLength: ApexStyle.s1)

                ApexActionButton(
                    "插入",
                    icon: "terminal",
                    tint: ApexStyle.secondary,
                    size: .small
                ) {
                    onInsertCommand(tab.content, false)
                }
                .disabled(tab.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                ApexActionButton(
                    "执行",
                    icon: "play.fill",
                    tint: ApexStyle.accent,
                    size: .small
                ) {
                    onInsertCommand(tab.content, true)
                }
                .disabled(tab.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                ApexIconButton(
                    icon: "floppy.disk",
                    label: "保存 (⌘S)",
                    size: 24,
                    iconSize: 11,
                    isSelected: true
                ) {
                    onSave()
                }
                .disabled(!tab.isDirty)
            }
            .padding(.horizontal, ApexStyle.s3)
            .padding(.vertical, ApexStyle.s2)

            Divider()

            NativeCodeEditor(
                text: $tab.content,
                showsFindBar: $showsFindBar,
                isReloading: false,
                palette: editorPalette
            )
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: ApexStyle.s2) {
                Text("\(tab.content.count) 字符 · \(lineCount) 行")
                    .font(.caption2)
                    .foregroundColor(ApexStyle.secondary)
                Spacer()
                Text(tab.group ?? "未分组")
                    .font(.caption2)
                    .foregroundColor(ApexStyle.secondary)
            }
            .padding(.horizontal, ApexStyle.s3)
            .padding(.vertical, ApexStyle.s1)
        }
        .onChange(of: tab.content) { _, _ in
            tab.savedNotice = nil
            tab.lastError = nil
        }
        .onChange(of: tab.title) { _, _ in
            tab.lastError = nil
        }
    }
}
