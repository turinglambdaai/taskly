import AppKit
import SwiftUI

/// Signed ARGB int as stored in the DB color column (DATA-FORMAT §2):
/// 0xFFRRGGBB reinterpreted as Int32.
func argbInt(hex: UInt32) -> Int64 {
    Int64(Int32(truncatingIfNeeded: 0xFF000000 | hex))
}

/// Create / edit a list: name, emoji, color.
struct ListEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let context: ListEditContext
    @State private var name = ""
    @State private var icon: String?
    @State private var color: Int64?
    @State private var emojiPickerVisible = false
    @State private var colorPickerVisible = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing ? model.t("dialogEditList") : model.t("dialogCreateList"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.theme.onSurface)

            // Quiet input: surface fill + 1px input border (quick-add language).
            TextField(model.t("dialogInputListName"), text: $name)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(model.theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(model.theme.inputBorder, lineWidth: 1))
                .focused($nameFocused)

            HStack(spacing: 24) {
                // Icon
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.t("dialogListIcon"))
                        .font(.system(size: 12))
                        .foregroundStyle(model.theme.secondaryText)
                    HStack(spacing: 6) {
                        Button {
                            emojiPickerVisible.toggle()
                        } label: {
                            ZStack {
                                Circle().fill(model.theme.accent)
                                Text(icon ?? "✚")
                                    .font(.system(size: 18))
                            }
                            .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $emojiPickerVisible) {
                            EmojiPickerGrid(selection: $icon)
                        }
                        if icon != nil {
                            Button(model.t("dialogClearIcon")) { icon = nil }
                                .font(.system(size: 12))
                                .foregroundStyle(model.theme.secondaryText)
                                .buttonStyle(.plain)
                        }
                    }
                }

                // Color
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.t("dialogListColor"))
                        .font(.system(size: 12))
                        .foregroundStyle(model.theme.secondaryText)
                    HStack(spacing: 6) {
                        Button {
                            colorPickerVisible.toggle()
                        } label: {
                            ZStack {
                                Circle().fill(Color(argb: color))
                                if color == nil {
                                    Image(systemName: "paintpalette")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $colorPickerVisible) {
                            ColorSwatchGrid(selection: $color)
                        }
                        if color != nil {
                            Button(model.t("dialogClearColor")) { color = nil }
                                .font(.system(size: 12))
                                .foregroundStyle(model.theme.secondaryText)
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(model.t("dialogCancel"))
                        .font(.system(size: 13))
                        .foregroundStyle(model.theme.secondaryText)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    commit()
                } label: {
                    Text(model.t("dialogConfirm"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(model.theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(model.theme.background)
        .onAppear {
            if case let .edit(list) = context.mode {
                name = list.name
                icon = list.icon
                color = list.color
            }
            nameFocused = true
        }
        .onExitCommand { dismiss() }
    }

    private var editing: Bool {
        if case .edit = context.mode { return true }
        return false
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch context.mode {
        case .create:
            model.createList(name: trimmed, icon: icon, color: color)
        case .edit(let list):
            model.updateList(list, name: trimmed, icon: icon, color: color)
        }
        dismiss()
    }
}

private struct EmojiPickerGrid: View {
    @Binding var selection: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var categoryId = Palette.emojiCategoryIds.first ?? "frequent"

    var body: some View {
        VStack(spacing: 10) {
            // Category tabs (Reminders-level coverage: 8 × 12).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Palette.emojiCategoryIds, id: \.self) { id in
                        Button {
                            categoryId = id
                        } label: {
                            Text(model.t("emojiCat_" + id))
                                .font(.system(size: 12, weight: categoryId == id ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .foregroundStyle(categoryId == id ? model.theme.accent : model.theme.secondaryText)
                                .background(
                                    categoryId == id ? model.theme.accent.opacity(0.1) : Color.clear,
                                    in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            let emojis = Palette.emojiCategories[categoryId] ?? []
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 6),
                spacing: 4) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selection = emoji
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 20))
                            .frame(width: 34, height: 34)
                            .background(
                                selection == emoji
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }
}

private struct ColorSwatchGrid: View {
    @Binding var selection: Int64?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Palette.listColors.enumerated()), id: \.offset) { index, color in
                Button {
                    selection = argbInt(hex: Palette.listColorsHex[index])
                    dismiss()
                } label: {
                    ZStack {
                        Circle().fill(color)
                        if selection == argbInt(hex: Palette.listColorsHex[index]) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }
}

/// About box (Help ▸ About) — the update/link/feedback hub and the
/// diagnostics surface (PRODUCT-SPEC §8).
struct AboutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? RivetGeneratedConfig.version
    }

    /// The diagnostics block a bug report starts from (PRODUCT-SPEC §8):
    /// release identity plus the `~/.taskly` contract paths. Labels are
    /// English fixed strings — machine-oriented like the CLI's --json.
    private var diagnosticsText: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #else
        arch = "unknown"
        #endif
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return """
        Taskly \(version) (macOS \(os.majorVersion).\(os.minorVersion), \(arch))
        Database: \(home)/.taskly/tasks.db
        Config: \(home)/.taskly/config.ini
        """
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsText, forType: .string)
        model.flashStatus(model.t("statusDiagnosticsCopied"))
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 44))
                .foregroundStyle(model.theme.accent)
            Text("Taskly v\(version)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.theme.onSurface)
            Text("© 2026 Taskly Team")
                .font(.system(size: 12))
                .foregroundStyle(model.theme.secondaryText)
            Text(model.t("aboutContent"))
                .font(.system(size: 12))
                .foregroundStyle(model.theme.secondaryText)
                .multilineTextAlignment(.center)
            Text(model.t("aboutLicense"))
                .font(.system(size: 11))
                .foregroundStyle(model.theme.secondaryText)
            HStack(spacing: 20) {
                Link(model.t("aboutWebsite"),
                     destination: URL(string: "https://taskly.jrtx.site")!)
                Link(model.t("aboutManual"),
                     destination: URL(string: "https://taskly.jrtx.site/manual.html")!)
            }
            .font(.system(size: 12))
            .tint(model.theme.accent)
            HStack(spacing: 20) {
                Link(model.t("aboutChangelog"),
                     destination: URL(string: "https://github.com/turinglambdaai/taskly/blob/main/CHANGELOG.md")!)
                Link(model.t("aboutReportIssue"),
                     destination: URL(string: "https://github.com/turinglambdaai/taskly/issues")!)
            }
            .font(.system(size: 12))
            .tint(model.theme.accent)
            Text(diagnosticsText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(model.theme.secondaryText)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            Button(model.t("aboutCopyDiagnostics")) { copyDiagnostics() }
                .font(.system(size: 12))
                .buttonStyle(.bordered)
                .tint(model.theme.accent)
            Button(model.t("dialogConfirm")) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(model.theme.accent)
        }
        .padding(28)
        .frame(width: 320)
        .background(model.theme.background)
    }
}

/// Update sheet (shared/spec/UPDATE.md): one phase machine driving check →
/// offer → download → install. A failed install leaves the running version
/// untouched; the download phase offers a Cancel button (issue #13) and a
/// stalled download surfaces a retryable error.
struct UpdateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44))
                .foregroundStyle(model.theme.accent)

            switch model.updatePhase {
            case .checking:
                ProgressView()

            case .available:
                Text(model.t("updateAvailableTitle"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.theme.onSurface)
                Text(model.t("updateAvailableBody", model.updateAvailableVersion))
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.secondaryText)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button(model.t("dialogCancel")) { dismiss() }
                    Button(model.t("updateRestart")) { model.installUpdate() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(model.theme.accent)
                }

            case .downloading:
                Text(model.t("updateDownloading"))
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.onSurface)
                ProgressView(value: Double(model.updateProgressPercent), total: 100)
                    .frame(width: 240)
                    .tint(model.theme.accent)
                Text("\(model.updateProgressPercent)%")
                    .font(.system(size: 12))
                    .foregroundStyle(model.theme.secondaryText)
                // The download can stall silently (issue #13) — the way out
                // must be a button, not "kill the app".
                Button(model.t("dialogCancel")) { model.cancelUpdateDownload() }

            case .upToDate:
                Text(model.t("updateUpToDate"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(model.theme.onSurface)
                Button(model.t("dialogConfirm")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(model.theme.accent)

            case .failed:
                Text(model.updateErrorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(model.t("dialogCancel")) { dismiss() }
                    Button(model.t("menuCheckUpdates")) { model.checkForUpdates() }
                }

            case .idle:
                EmptyView()
            }
        }
        .padding(28)
        .frame(width: 360)
        .background(model.theme.background)
        .interactiveDismissDisabled(model.updatePhase == .downloading)
    }
}
