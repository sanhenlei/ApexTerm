import SwiftUI
import AppKit
import ApexCore

/// Horizontal collapsible quick command bar docked at the bottom of the workspace.
/// Backed by the file-based command library: click types the command into the terminal
/// without executing; ⌥-click types and runs it immediately.
public struct QuickCommandBarView: View {
    @ObservedObject private var library = LibraryStore.shared
    public let onRunCommand: (_ command: String, _ executeNow: Bool) -> Void
    public let onOpenFile: (LibraryFile) -> Void
    @Binding public var isVisible: Bool

    @State private var selectedCategory: String = "全部"
    @State private var pendingTemplate: CommandTemplate?
    @State private var variableValues: [String: String] = [:]

    /// A command string awaiting variable values in the input sheet.
    private struct CommandTemplate: Identifiable {
        let id = UUID()
        let title: String
        let command: String
    }

    public init(
        isVisible: Binding<Bool>,
        onRunCommand: @escaping (_ command: String, _ executeNow: Bool) -> Void,
        onOpenFile: @escaping (LibraryFile) -> Void
    ) {
        self._isVisible = isVisible
        self.onRunCommand = onRunCommand
        self.onOpenFile = onOpenFile
    }

    private static let ungroupedCategory = "未分组"

    private var allCategories: [String] {
        var list = Set(library.commands.compactMap(\.group)).sorted()
        if library.commands.contains(where: { $0.group == nil }) {
            list.append(Self.ungroupedCategory)
        }
        return ["全部"] + list
    }

    private var filteredCommands: [LibraryFile] {
        guard selectedCategory != "全部" else { return library.commands }
        if selectedCategory == Self.ungroupedCategory {
            return library.commands.filter { $0.group == nil }
        }
        return library.commands.filter { $0.group == selectedCategory }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: ApexStyle.s2) {
                // Category pills + command pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ApexStyle.sCompact) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(ApexStyle.accent)
                            Text("快捷命令")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ApexStyle.primary)
                        }
                        .padding(.trailing, 4)

                        ForEach(allCategories, id: \.self) { cat in
                            ApexPillButton(
                                title: cat,
                                isSelected: selectedCategory == cat,
                                action: { selectedCategory = cat }
                            )
                        }

                        Divider().frame(height: 14)

                        ForEach(filteredCommands) { file in
                            CommandPill(file: file) {
                                triggerCommand(file)
                            }
                        }

                        ApexPillButton(title: "添加", icon: "plus") {
                            addCommand()
                        }
                        .help("新建快捷命令文件并在编辑器中打开")
                    }
                    .padding(.horizontal, ApexStyle.s4)
                    .padding(.vertical, 6)
                }

                Spacer(minLength: 4)

                // Hide bar button
                ApexIconButton(
                    icon: "xmark",
                    label: "隐藏快捷命令栏 (⌘⇧B)",
                    size: 22,
                    iconSize: 9
                ) {
                    withAnimation(ApexStyle.hoverTransition) {
                        isVisible = false
                    }
                }
                .padding(.trailing, ApexStyle.s4)
            }
            .frame(height: 38)
            .background(ApexStyle.subtleSurface.opacity(0.65))
        }
        .sheet(item: $pendingTemplate) { template in
            VariableInputSheet(
                title: template.title,
                command: template.command,
                variableValues: $variableValues,
                onConfirm: { resolved in
                    onRunCommand(resolved, false)
                    pendingTemplate = nil
                },
                onCancel: {
                    pendingTemplate = nil
                }
            )
            .apexTheme()
        }
    }

    // MARK: - Actions

    private func triggerCommand(_ file: LibraryFile) {
        let raw = (try? library.read(file)) ?? ""
        guard !raw.isEmpty else { return }
        let executeNow = NSEvent.modifierFlags.contains(.option)
        let variables = Snippet.extractVariables(in: raw)
        if variables.isEmpty {
            onRunCommand(Snippet.resolved(command: raw, context: [:]), executeNow)
        } else {
            variableValues = Dictionary(uniqueKeysWithValues: variables.map { ($0, "") })
            pendingTemplate = CommandTemplate(title: file.title, command: raw)
        }
    }

    private func addCommand() {
        if let file = try? library.createFile(kind: .command, title: "新命令", content: "") {
            onOpenFile(file)
        }
    }
}

/// Modal dialog prompting values for `{{var}}` placeholders in a command template.
/// Shared with the command palette (which passes a `Snippet`).
struct VariableInputSheet: View {
    let title: String
    let command: String
    @Binding var variableValues: [String: String]
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    init(snippet: Snippet, variableValues: Binding<[String: String]>, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.init(title: snippet.title, command: snippet.command, variableValues: variableValues, onConfirm: onConfirm, onCancel: onCancel)
    }

    init(title: String, command: String, variableValues: Binding<[String: String]>, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.command = command
        self._variableValues = variableValues
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private var variables: [String] {
        Snippet.extractVariables(in: command)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ApexStyle.s4) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ApexStyle.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text("请为以下变量输入参数值")
                        .font(.caption)
                        .foregroundColor(ApexStyle.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("原始命令模板：")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ApexStyle.secondary)
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ApexStyle.surface, in: RoundedRectangle(cornerRadius: ApexStyle.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: ApexStyle.controlRadius).stroke(ApexStyle.border, lineWidth: 1))
            }

            VStack(spacing: ApexStyle.s3) {
                ForEach(variables, id: \.self) { v in
                    HStack(spacing: ApexStyle.s2) {
                        Text(v)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(ApexStyle.accent)
                            .frame(width: 120, alignment: .trailing)

                        TextField("输入 \(v)...", text: Binding(
                            get: { variableValues[v] ?? "" },
                            set: { variableValues[v] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            submitIfValid()
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            HStack {
                Spacer()
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut(.cancelAction)

                Button("插入 (↵)") {
                    submitIfValid()
                }
                .apexProminentButton()
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ApexStyle.s5)
        .frame(width: 480)
    }

    private func submitIfValid() {
        onConfirm(Snippet.resolved(command: command, context: variableValues))
    }
}

private struct CommandPill: View {
    let file: LibraryFile
    let onTrigger: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTrigger) {
            Text(file.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: ApexStyle.controlRadius)
                        .fill(isHovered ? ApexStyle.surface : ApexStyle.subtleSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ApexStyle.controlRadius)
                        .stroke(isHovered ? ApexStyle.accent.opacity(0.4) : ApexStyle.border.opacity(0.7), lineWidth: 0.75)
                )
                .shadow(color: isHovered ? Color.black.opacity(0.06) : Color.clear, radius: 2, x: 0, y: 1)
                .foregroundColor(isHovered ? ApexStyle.primary : ApexStyle.primary.opacity(0.85))
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(ApexStyle.springSnappy, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("\(file.title)\n点击输入到终端（不执行），按住 ⌥ 点击立即执行")
    }
}
