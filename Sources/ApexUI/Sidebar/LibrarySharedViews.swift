import SwiftUI
import AppKit
import ApexCore

/// Shared row for library files: title only, content stays hidden until opened.
/// Clicking the row opens the editor for both kinds (no accidental terminal input);
/// command rows additionally show a hover "fill" button that types into the
/// terminal without executing (⌥-click fills and runs). The hover pencil opens the editor.
struct LibraryFileRow: View {
    let file: LibraryFile
    let icon: String
    let iconColor: Color
    let primaryActionLabel: String
    let showsExecuteHint: Bool
    let showsFillButton: Bool
    let onPrimary: (_ executeNow: Bool) -> Void
    let onFill: ((_ executeNow: Bool) -> Void)?
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onPrimary(NSEvent.modifierFlags.contains(.option))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 13)

                Text(file.title)
                    .font(.system(size: 12))
                    .foregroundColor(ApexStyle.primary)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if showsFillButton {
                    ApexIconButton(
                        icon: "arrow.down.to.line.compact",
                        label: "填入终端",
                        size: 18,
                        iconSize: 8,
                        tint: isHovered ? ApexStyle.success : nil
                    ) {
                        onFill?(NSEvent.modifierFlags.contains(.option))
                    }
                    .opacity(isHovered ? 1.0 : 0.0)
                    .help("填入到终端不执行（⌥+点击填入并立即执行）")
                }

                ApexIconButton(
                    icon: "pencil",
                    label: "编辑 \(file.title)",
                    size: 18,
                    iconSize: 8,
                    tint: isHovered ? ApexStyle.accent : nil
                ) {
                    onOpen()
                }
                .opacity(isHovered ? 1.0 : 0.0)
            }
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: ApexStyle.badgeRadius)
                    .fill(isHovered ? ApexStyle.primary.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsFillButton
              ? "点击打开编辑器；悬停「↓」填入终端不执行（⌥+点击立即执行）"
              : primaryActionLabel)
        .onHover { hovering in
            withAnimation(ApexStyle.hoverTransition) {
                isHovered = hovering
            }
        }
    }
}

/// Disclosure label for a library group (= workdir subdirectory). The context menu
/// creates a file directly inside this group, plus rename/delete.
struct LibraryGroupLabel: View {
    let name: String
    let count: Int
    let createLabel: String
    let onCreate: (() -> Void)?
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(ApexStyle.secondary)
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ApexStyle.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(ApexStyle.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: ApexStyle.badgeRadius))
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let onCreate {
                Button {
                    onCreate()
                } label: {
                    Label(createLabel, systemImage: "plus.circle")
                }
                Divider()
            }
            Button("重命名分组") { onRename() }
            Divider()
            Button("删除分组", role: .destructive) { onDelete() }
        }
    }
}

/// Bottom toast mirroring the sessions sidebar feedback pattern.
struct LibraryToastOverlay: View {
    let message: String?

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ApexStyle.warning)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ApexStyle.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .apexGlassCard(cornerRadius: 14, material: .regularMaterial, borderColor: Color.primary.opacity(0.12), shadowRadius: 8)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}

/// Empty state shown when the library workdir has not been configured yet.
struct LibraryWorkdirEmptyState: View {
    let onChoose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("尚未选择工作目录")
                    .font(.headline)
                    .foregroundColor(ApexStyle.primary)
                Text("快捷命令与笔记以文件形式保存在工作目录中，\n可放入 iCloud Drive 或其他同步盘实现多设备同步。")
                    .font(.subheadline)
                    .foregroundStyle(ApexStyle.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            ApexActionButton(
                "选择工作目录",
                icon: "folder",
                tint: ApexStyle.accent,
                size: .regular,
                isProminent: true
            ) {
                onChoose()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
