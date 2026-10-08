import SwiftUI

struct FavoriteFolderManagementContent: View {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var controller: AccountLibraryManagementController
    @Environment(\.favoriteFolderManagementActions) private var actions

    private var accountMID: Int? { controller.api.requestSnapshot(purpose: .interaction).currentUserMID }

    var body: some View {
        Group {
            if viewModel.favoriteFolders.isEmpty {
                LibraryEmptyRow(title: "还没有收藏夹", systemImage: "folder")
            }
            ForEach(viewModel.favoriteFolders) { folder in
                NavigationLink {
                    FavoriteFolderContentPage(folder: folder, viewModel: viewModel)
                } label: { FavoriteFolderRow(folder: folder, showsStatus: true, showsDisclosureIndicator: false) }
                .contextMenu {
                    if folder.canManage(accountMID: accountMID), !folder.isDefaultFolder {
                        Button("编辑收藏夹", systemImage: "pencil") { actions?.edit(folder) }
                        Button("删除收藏夹", systemImage: "trash", role: .destructive) { actions?.delete(folder) }
                    }
                }
                .swipeActions {
                    if folder.canManage(accountMID: accountMID), !folder.isDefaultFolder {
                        Button("删除", role: .destructive) { actions?.delete(folder) }
                        Button("编辑") { actions?.edit(folder) }
                    }
                }
            }
        }
        .disabled(controller.isBusy)
    }
}

private struct FavoriteFolderManagementActions {
    let edit: (FavoriteFolder?) -> Void
    let delete: (FavoriteFolder) -> Void
}

private extension EnvironmentValues {
    @Entry var favoriteFolderManagementActions: FavoriteFolderManagementActions? = nil
}

struct FavoriteFolderManagementModifier: ViewModifier {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var controller: AccountLibraryManagementController
    @EnvironmentObject private var sessionStore: SessionStore
    let enabled: Bool
    @State private var editorFolder: FavoriteFolder?
    @State private var showsEditor = false
    @State private var showsSort = false
    @State private var pendingDeletion: FavoriteFolder?

    private var accountMID: Int? { controller.api.requestSnapshot(purpose: .interaction).currentUserMID }

    func body(content: Content) -> some View {
        content
            .environment(\.favoriteFolderManagementActions, enabled ? FavoriteFolderManagementActions(
                edit: edit, delete: { pendingDeletion = $0 }
            ) : nil)
            .toolbar {
                if enabled {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("创建收藏夹", systemImage: "folder.badge.plus") { edit(nil) }
                            Button("收藏夹排序", systemImage: "arrow.up.arrow.down") { showsSort = true }
                                .disabled(viewModel.favoriteFolders.count < 2 || !viewModel.favoriteFolders.allSatisfy { $0.canManage(accountMID: accountMID) })
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("收藏夹管理")
                        .accessibilityIdentifier("library.favorites.actions")
                        .disabled(controller.isBusy)
                    }
                }
            }
            .sheet(isPresented: $showsEditor) {
                FavoriteFolderEditor(folder: editorFolder, controller: controller) { await viewModel.refreshFavorites() }
            }
            .sheet(isPresented: $showsSort) {
                FavoriteFolderSortSheet(folders: viewModel.favoriteFolders, controller: controller) { await viewModel.refreshFavorites() }
            }
            .confirmationDialog("删除「\(pendingDeletion?.displayTitle ?? "")」？",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
                Button("删除收藏夹", role: .destructive) {
                    guard let folder = pendingDeletion else { return }
                    pendingDeletion = nil
                    Task {
                        _ = await controller.mutate(purpose: .interaction) { context in
                            try await controller.api.deleteFavoriteFolder(folder, context: context)
                        }
                        await viewModel.refreshFavorites()
                        viewModel.favoriteFolderEntries[folder.id] = nil
                        viewModel.favoriteFolderEntryStates[folder.id] = nil
                    }
                }
                Button("取消", role: .cancel) { pendingDeletion = nil }
            } message: { Text("该收藏夹中的收藏关系将被移除，此操作不能撤销。其他收藏夹不受影响。") }
            .alert("管理结果", isPresented: Binding(get: { enabled && controller.message != nil }, set: { if !$0 { Task { @MainActor in controller.message = nil } } })) {
                Button("好") { controller.message = nil }
            } message: { Text(controller.message ?? "") }
            .onChange(of: enabled) { _, value in if !value { resetPresentation() } }
            .onChange(of: sessionStore.interactionAccountCredentialVersion) { _, _ in resetPresentation() }
    }

    private func resetPresentation() {
        showsEditor = false; showsSort = false; editorFolder = nil; pendingDeletion = nil
    }
    private func edit(_ folder: FavoriteFolder?) { editorFolder = folder; showsEditor = true }
}

private struct FavoriteFolderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    let folder: FavoriteFolder?
    @ObservedObject var controller: AccountLibraryManagementController
    let reload: () async -> Void
    @State private var title = ""
    @State private var intro = ""
    @State private var isPrivate = false
    @State private var loadedFolder: FavoriteFolder?
    @State private var loading = true
    @State private var error: String?
    @State private var accountContext: LibraryManagementContext?

    var body: some View {
        NavigationStack {
            Form {
                if loading { ProgressView("正在读取收藏夹") }
                if let error { Text(error).foregroundStyle(.red) }
                TextField("名称", text: $title)
                TextField("简介", text: $intro, axis: .vertical)
                    .lineLimit(3...6)
                Toggle("私密收藏夹", isOn: $isPrivate)
            }
            .navigationTitle(folder == nil ? "创建收藏夹" : "编辑收藏夹")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(controller.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            guard let accountContext else { return }
                            let ok = await controller.mutate(purpose: .interaction) { _ in
                                try await controller.api.saveFavoriteFolder(folder: loadedFolder, title: title, intro: intro,
                                                                           isPrivate: isPrivate, context: accountContext)
                            }
                            if ok { await reload(); dismiss() }
                            else { error = controller.message; controller.message = nil }
                        }
                    }
                    .disabled(loading || controller.isBusy || accountContext == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                do {
                    let context = try await controller.api.libraryManagementContext(purpose: .interaction)
                    accountContext = context
                    if let folder {
                        loadedFolder = try await controller.api.fetchManagedFavoriteFolder(id: folder.id, context: context)
                        guard let loadedFolder, loadedFolder.canManage(accountMID: context.snapshot.currentUserMID), !loadedFolder.isDefaultFolder else {
                            throw BiliAPIError.api(code: -400, message: "该收藏夹不支持编辑")
                        }
                        title = loadedFolder.displayTitle; intro = loadedFolder.intro ?? ""
                        isPrivate = loadedFolder.isPrivateFolder
                    }
                } catch { self.error = error.localizedDescription; accountContext = nil }
                loading = false
            }
        }
        .interactiveDismissDisabled(controller.isBusy)
        .onChange(of: sessionStore.interactionAccountCredentialVersion) { _, _ in dismiss() }
    }
}

private struct FavoriteFolderSortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    let folders: [FavoriteFolder]
    @ObservedObject var controller: AccountLibraryManagementController
    let reload: () async -> Void
    @State private var ordered: [FavoriteFolder] = []
    @State private var context: LibraryManagementContext?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(ordered) { folder in
                    FavoriteFolderRow(folder: folder, showsStatus: true)
                        .moveDisabled(folder.isDefaultFolder)
                }
                .onMove { indices, destination in
                    var next = ordered
                    next.move(fromOffsets: indices, toOffset: destination)
                    // Default folders stay at their server-defined positions.
                    guard ordered.enumerated().filter({ $0.element.isDefaultFolder }).allSatisfy({ next[$0.offset].id == $0.element.id }) else { return }
                    ordered = next
                }
            }
            .environment(\.editMode, .constant(.active))
            .disabled(controller.isBusy)
            .navigationTitle("收藏夹排序")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(controller.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            guard let context else { return }
                            let ok = await controller.mutate(purpose: .interaction) { _ in
                                try await controller.api.sortFavoriteFolders(ids: ordered.map(\.id), context: context)
                            }
                            if ok { await reload(); dismiss() }
                            else { error = controller.message; controller.message = nil }
                        }
                    }.disabled(context == nil || controller.isBusy)
                }
            }
            .task {
                ordered = folders
                do { context = try await controller.api.libraryManagementContext(purpose: .interaction) }
                catch { self.error = error.localizedDescription }
            }
        }
        .interactiveDismissDisabled(controller.isBusy)
        .onChange(of: sessionStore.interactionAccountCredentialVersion) { _, _ in dismiss() }
    }
}
