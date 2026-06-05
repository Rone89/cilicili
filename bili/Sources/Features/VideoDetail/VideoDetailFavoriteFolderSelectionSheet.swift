import SwiftUI

struct FavoriteFolderSelectionSheet: View {
    @ObservedObject var store: VideoDetailFavoriteFolderRenderStore
    let loadFavoriteFolders: (Bool) async -> Void
    let saveFavoriteFolders: (Set<Int>) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFolderIDs = Set<Int>()
    @State private var didInitializeSelection = false

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .navigationTitle("选择收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            let didSave = await saveFavoriteFolders(selectedFolderIDs)
                            if didSave {
                                Haptics.success()
                                dismiss()
                            }
                        }
                    }
                    .disabled(store.favoriteFolderState.isLoading || store.isMutatingInteraction)
                }
            }
            .task {
                await loadFavoriteFolders(false)
                initializeSelectionIfNeeded()
            }
            .onChange(of: store.favoriteFolders) { _, _ in
                initializeSelectionIfNeeded()
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var content: some View {
        if store.favoriteFolders.isEmpty && store.favoriteFolderState.isLoading {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取收藏夹")
                        .foregroundStyle(.secondary)
                }
            }
        } else if store.favoriteFolders.isEmpty,
                  case .failed(let message) = store.favoriteFolderState {
            Section {
                ContentUnavailableView(
                    "无法读取收藏夹",
                    systemImage: "exclamationmark.circle",
                    description: Text(message)
                )

                Button {
                    Task {
                        await loadFavoriteFolders(true)
                        initializeSelectionIfNeeded(force: true)
                    }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
            }
        } else if store.favoriteFolders.isEmpty {
            Section {
                ContentUnavailableView(
                    "暂无收藏夹",
                    systemImage: "folder",
                    description: Text("请先在 B 站创建收藏夹。")
                )
            }
        } else {
            Section {
                ForEach(store.favoriteFolders) { folder in
                    Toggle(isOn: Binding(
                        get: { selectedFolderIDs.contains(folder.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedFolderIDs.insert(folder.id)
                            } else {
                                selectedFolderIDs.remove(folder.id)
                            }
                        }
                    )) {
                        FavoriteFolderSelectionRow(folder: folder)
                    }
                    .toggleStyle(.switch)
                }
            } footer: {
                Text("可同时收藏到多个文件夹；关闭所有开关会取消收藏。")
            }
        }
    }

    private func initializeSelectionIfNeeded(force: Bool = false) {
        guard force || !didInitializeSelection else { return }
        selectedFolderIDs = Set(store.favoriteFolders.filter(\.isFavorited).map(\.id))
        didInitializeSelection = true
    }
}

private struct FavoriteFolderSelectionRow: View {
    let folder: FavoriteFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(folder.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("\(folder.mediaCount ?? 0) 个内容")
                if folder.isFavorited {
                    Text("当前已收藏")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
