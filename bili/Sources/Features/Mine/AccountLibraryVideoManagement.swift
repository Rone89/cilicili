import SwiftUI

struct AccountLibraryManagedVideoRow: View {
    let item: AccountVideoEntry
    let timestampTitle: String
    let isEditing: Bool
    let canManage: Bool
    let remove: () -> Void

    var body: some View {
        Group {
            if isEditing {
                LibraryVideoRow(item: item, timestampTitle: timestampTitle)
            } else {
                VideoRouteLink(item.videoItem) {
                    LibraryVideoRow(item: item, timestampTitle: timestampTitle)
                }
            }
        }
        .tag(item.id)
        .accessibilityIdentifier("library.video.\(item.id)")
        .swipeActions {
            if canManage {
                Button("移除", role: .destructive, action: remove)
            }
        }
        .contextMenu {
            if canManage {
                Button("移除", systemImage: "trash", role: .destructive, action: remove)
            }
        }
    }
}

struct AccountLibraryVideoManagementModifier: ViewModifier {
    @ObservedObject var controller: AccountLibraryManagementController
    let enabled: Bool
    let entries: [AccountVideoEntry]
    let source: FavoriteFolder?
    let folders: [FavoriteFolder]
    @Binding var selection: Set<String>
    @Binding var editMode: EditMode
    let reload: () async -> Void
    @State private var confirmsRemoval = false
    @State private var transferAction: LibraryVideoManagementAction?

    func body(content: Content) -> some View {
        content
            .environment(\.editMode, $editMode)
            .nativeBottomScrollEdgeBlur()
            .nativeBottomScrollEdgeBlurVisibility(isHidden: !enabled || !editMode.isEditing)
            .toolbar {
                if enabled {
                    ToolbarItem(placement: .topBarTrailing) {
                        if controller.isBusy { ProgressView() }
                        else {
                            Button(editMode.isEditing ? "完成" : "选择") {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                            .disabled(entries.isEmpty)
                            .accessibilityIdentifier("library.manage.select")
                        }
                    }
                    if editMode.isEditing {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button(selection.count == selectableIDs.count ? "取消全选" : "全选") {
                                selection = selection.count == selectableIDs.count ? [] : selectableIDs
                            }
                            .accessibilityIdentifier("library.manage.selectAll")
                            Spacer()
                            if source != nil {
                                Button("复制", systemImage: "doc.on.doc") { transferAction = .copy(0) }
                                    .disabled(selection.isEmpty)
                                    .accessibilityIdentifier("library.manage.copy")
                                Button("移动", systemImage: "folder") { transferAction = .move(0) }
                                    .disabled(selection.isEmpty)
                                    .accessibilityIdentifier("library.manage.move")
                            }
                            Button("移除", systemImage: "trash", role: .destructive) { confirmsRemoval = true }
                                .disabled(selection.isEmpty)
                                .accessibilityIdentifier("library.manage.remove")
                        }
                    }
                }
            }
            .disabled(controller.isBusy)
            .confirmationDialog("移除所选的 \(selection.count) 项？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("移除", role: .destructive) { run(.remove) }
                    .accessibilityIdentifier("library.manage.confirmRemove")
                Button("取消", role: .cancel) {}
            } message: {
                Text(source == nil ? "仅从稍后再看中移除。" : "仅取消当前收藏夹内的收藏，不影响其他收藏夹。")
            }
            .sheet(isPresented: Binding(get: { transferAction != nil }, set: { if !$0 { transferAction = nil } })) {
                NavigationStack {
                    List {
                        ForEach(folders.filter { $0.id != source?.id }) { folder in
                            Button {
                                guard let action = transferAction else { return }
                                transferAction = nil
                                if case .move = action { run(.move(folder.id)) }
                                else { run(.copy(folder.id)) }
                            } label: { FavoriteFolderRow(folder: folder) }
                        }
                        if folders.filter({ $0.id != source?.id }).isEmpty {
                            Text("没有其他收藏夹，请先创建一个收藏夹")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .nativeBottomScrollEdgeBlur()
                    .navigationTitle("选择目标收藏夹")
                    .toolbar { Button("取消") { transferAction = nil } }
                }
            }
            .alert("管理结果", isPresented: Binding(get: { enabled && controller.message != nil }, set: { if !$0 { Task { @MainActor in controller.message = nil } } })) {
                Button("好") { controller.message = nil }
            } message: { Text(controller.message ?? "") }
            .onChange(of: entries.map(\.id)) { _, _ in selection.formIntersection(selectableIDs) }
            .onChange(of: editMode) { _, mode in
                if !mode.isEditing { selection = []; transferAction = nil; confirmsRemoval = false }
            }
            .onChange(of: enabled) { _, value in
                if !value { editMode = .inactive; selection = []; transferAction = nil; confirmsRemoval = false }
            }
            .onDisappear { editMode = .inactive; selection = [] }
    }

    private var selectableIDs: Set<String> { Set(entries.filter { ($0.aid ?? 0) > 0 }.map(\.id)) }
    private func run(_ action: LibraryVideoManagementAction) {
        let selected = entries.filter { selection.contains($0.id) }
        Task {
            await controller.perform(entries: selected, source: source, action: action)
            selection = []
            // Even a timeout can follow a committed server mutation: always reconcile.
            await reload()
        }
    }
}

struct LibrarySearchField: View {
    @Binding var text: String
    let prompt: String
    let identifier: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { isFocused = false }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
    }
}
