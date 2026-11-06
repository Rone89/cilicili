import Combine
import QuartzCore
import SwiftUI
import UIKit

/// 被 UIKit 宿主隔断、需要显式注入评论行内容的 SwiftUI 环境。
@MainActor
struct VideoDetailCommentsCellEnvironment {
    let dependencies: AppDependencies
    let libraryStore: LibraryStore
    let appTintColor: Color
    let commentLikeTarget: CommentLikeTarget?
    let openAppURL: ((URL) -> Void)?
}

/// 评论页 UITableView 宿主：表格视图同时充当页面滚动容器。
///
/// 之所以由列表自己滚动（而不是塞进外层 `UIScrollView`），是因为非滚动列表无法按
/// 可视区域复用 cell——那样等价于一次性布局全部行，得不到复用收益。外层以
/// `contentInset.top = 播放器展开高度` 保留原有“播放器随滚动收缩”的手感。
@MainActor
struct VideoDetailCommentsTableViewHost: UIViewRepresentable {
    let store: VideoDetailCommentsRenderStore
    let actions: VideoDetailCommentsSectionActions
    let style: CommentSectionStyle
    let horizontalPadding: CGFloat
    let ownerMID: Int?
    let cellEnvironment: VideoDetailCommentsCellEnvironment
    let context: VideoDetailCommentsPageContext

    func makeCoordinator() -> Coordinator {
        Coordinator(props: coordinatorProps)
    }

    func makeUIView(context: Context) -> VideoDetailCommentsTableView {
        let view = Coordinator.makeTableView()
        view.delegate = context.coordinator
        context.coordinator.attach(to: view, scrollAdjustment: self.context.scrollAdjustment)
        return view
    }

    func updateUIView(_ view: VideoDetailCommentsTableView, context: Context) {
        context.coordinator.update(
            props: coordinatorProps,
            scrollAdjustment: self.context.scrollAdjustment
        )
    }

    static func dismantleUIView(
        _ view: VideoDetailCommentsTableView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    private var coordinatorProps: Coordinator.Props {
        Coordinator.Props(
            store: store,
            actions: actions,
            style: style,
            horizontalPadding: horizontalPadding,
            ownerMID: ownerMID,
            cellEnvironment: cellEnvironment,
            tab: context.tab,
            topInset: context.topInset,
            bottomInset: context.bottomInset,
            minimumPlayerHeight: context.minimumPlayerHeight,
            isActive: context.isActive,
            showsBottomEdgeEffect: context.showsBottomEdgeEffect,
            onScrollOffsetChange: context.onScrollOffsetChange,
            onScrollPhaseChange: context.onScrollPhaseChange
        )
    }
}

// MARK: - 表格视图

@MainActor
final class VideoDetailCommentsTableView: UITableView {
    var onLayout: (() -> Void)?
    private let bottomEdgeBinding = VideoDetailBottomEdgeEffectBinding()
    private var bottomEdgeEnabled = false
    private var bottomEdgeActive = false

    /// 与外壳滚动宿主一致的软性底部边缘（.soft + 工具栏容器交互）。
    /// 不配置时 `UIScrollView.bottomEdgeEffect` 默认是 .hard，和简介页不一致。
    func configureBottomEdgeEffect(enabled: Bool, isActiveContent: Bool) {
        bottomEdgeEnabled = enabled
        bottomEdgeActive = isActiveContent
        updateBottomEdgeBinding()
    }

    override init(frame: CGRect, style: UITableView.Style) {
        super.init(frame: frame, style: style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBottomEdgeBinding()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
        updateBottomEdgeBinding()
    }

    private func updateBottomEdgeBinding() {
        guard bottomEdgeEnabled, window != nil,
              let target = VideoDetailBottomEdgeEffectBinding.toolbarTarget(from: self)
        else {
            bottomEdgeBinding.detach()
            return
        }
        bottomEdgeBinding.update(
            scrollView: self,
            container: target.toolbar,
            enabled: true,
            isActiveContent: bottomEdgeActive
        )
    }

    /// 减速途中触摸即停（触摸经响应链到达时触发）。注意不要用额外的手势
    /// 识别器实现这个功能：它在减速触摸时立即 began，会把表格 pan 手势按
    /// 互斥规则强制 fail——那次触摸无法继续拖拽，手感明显"不跟手"。
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard isDecelerating else { return }
        // 写入 contentOffset 会终止减速；同值赋值可能被按 no-op 忽略，
        // 因此沿滚动方向微调 1pt，肉眼不可见但必定打断减速。
        let offset = contentOffset
        setContentOffset(
            CGPoint(x: offset.x, y: offset.y + 1),
            animated: false
        )
    }
}

// MARK: - 行 cell

/// 直持 `UIHostingController` 的评论 cell。
///
/// 不用 `UIHostingConfiguration`：它在 cell 复用换内容时是异步更新的，自适配
/// 会量到"上一份内容"的高度（真实设备上表现为错高空壳、行间距离漂移）。
/// 这里在配置时同步替换 `rootView`，配合外部提供的精确行高，内容与高度永远
/// 同源。行高由 host 的协调器给出（离屏种子 + 显示捕获），`sizingOptions`
/// 关闭自带的尺寸联动。
@MainActor
final class VideoDetailCommentContentCell: UITableViewCell {
    private var hostingController: UIHostingController<AnyView>?

    /// `.plain` 样式会给 cell 配默认 `backgroundConfiguration`
    /// （`tableCellPlainBackgroundColor`，浅色纯白/深色纯黑），它绘制在
    /// `backgroundColor` 之上，会把页面自己的分组灰底完全盖住。清掉这一层，
    /// 让列表与简介页共用 `VideoDetailTheme.background`（#F2F2F7）。
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        backgroundConfiguration = .clear()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(rootView: AnyView) {
        if let hostingController {
            hostingController.rootView = rootView
            return
        }
        let controller = UIHostingController(rootView: rootView)
        controller.sizingOptions = []
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        hostingController = controller
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostingController?.rootView = AnyView(EmptyView())
    }
}

// MARK: - 协调器

@MainActor
extension VideoDetailCommentsTableViewHost {
    final class Coordinator: NSObject, UITableViewDelegate {
        nonisolated enum Item: Hashable {
            case header
            case loading
            case error(String)
            case empty
            case spacer
            case comment(Int)
            case footer
        }

        struct Props {
            let store: VideoDetailCommentsRenderStore
            let actions: VideoDetailCommentsSectionActions
            let style: CommentSectionStyle
            let horizontalPadding: CGFloat
            let ownerMID: Int?
            let cellEnvironment: VideoDetailCommentsCellEnvironment
            let tab: VideoDetailContentTab
            let topInset: CGFloat
            let bottomInset: CGFloat
            let minimumPlayerHeight: CGFloat
            let isActive: Bool
            let showsBottomEdgeEffect: Bool
            let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
            let onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
        }

        private enum SectionID {
            static let main = 0
        }

        private struct HeaderSignature: Equatable {
            let replyCountText: String?
            let selectedSort: CommentSort
        }

        private struct FooterSignature: Equatable {
            let loadMoreState: LoadingState
            let hasMoreComments: Bool
        }

        /// 列表顶部留白：外壳 `padding(.top, 12)` + 内容页 `topPadding` 8。
        private static let listTopPadding: CGFloat = 20
        private static let cellReuseIdentifier = "comments.cell"
        /// 未测量行的估算高度：接近典型评论行（头像 + 两行文本），减小减速距离偏差。
        private static let defaultEstimatedRowHeight: CGFloat = 96
        static let logsHeightDebug = ProcessInfo.processInfo.arguments.contains("--ui-test-comment-pagination")

        private var props: Props
        private weak var tableView: VideoDetailCommentsTableView?
        private var dataSource: UITableViewDiffableDataSource<Int, Item>?
        private var storeCancellable: AnyCancellable?
        private var isAttached = false

        private var refreshScheduled = false
        private var layoutAdjustmentScheduled = false
        private var itemsByID: [Int: VideoDetailCommentDisplayItem] = [:]
        private var lastHeaderSignature: HeaderSignature?
        private var lastFooterSignature: FooterSignature?
        private var lastSelectedSort: CommentSort?
        private var appliedTopInset: CGFloat = 0
        private var lastAdjustmentToken: Int?
        private var pendingScrollAdjustment: VideoDetailScrollAdjustment?
        private var pendingVirtualOffset: CGFloat?
        private var lastReportedVirtualOffset: CGFloat?
        private var lastPhase: ScrollPhase = .idle
        /// 上次已发起的分页游标：同一游标只发一次，成功/失败后清空，
        /// 允许下一次 footer 进入可见区时自然重试（不对齐时间节流，对齐 PiliPod）。
        private var requestedLoadMoreToken: Int?
        private var previousLoadMoreState: LoadingState = .idle
        private var consecutiveLoadMoreFailures = 0
        /// 行高缓存：以“首次真实显示时系统自适配出的高度”为准，之后冻结。
        /// 不做任何离屏预测——SwiftUI 行内容里有随提议高度伸缩的弹性视图
        /// （整行回复按钮的占位），离屏测高在 101/102 分别测矮（重叠）和测高
        /// （大段空白），只有系统自适配 + 渲染时记录的高度是权威值。
        private var cachedRowHeights: [Item: CGFloat] = [:]
        /// 离屏测量的估算种子：行内容已无随提议伸缩的弹性视图（整行回复按钮
        /// 改为 overlay 承载），测量结果与真实渲染一致。种子只参与 UIKit 的
        /// 偏移数学（estimatedHeightForRowAt），首屏显示仍以自适配为准。
        private var seededHeights: [Item: CGFloat] = [:]
        private var lastCachedWidth: CGFloat = 0
        private lazy var sizingHostController: UIHostingController<AnyView> = {
            let controller = UIHostingController(rootView: AnyView(EmptyView()))
            controller.sizingOptions = []
            controller.safeAreaRegions = []
            controller.view.backgroundColor = .clear
            return controller
        }()
        private var suppressionScopeID = UUID()

        init(props: Props) {
            self.props = props
            super.init()
        }

        // MARK: 生命周期

        static func makeTableView() -> VideoDetailCommentsTableView {
            let view = VideoDetailCommentsTableView(frame: .zero, style: .plain)
            view.backgroundColor = .clear
            view.separatorStyle = .none
            // 渲染走系统自适配；估算用精确种子（seedHeight），显示后回填冻结。
            view.rowHeight = UITableView.automaticDimension
            view.estimatedRowHeight = Coordinator.defaultEstimatedRowHeight
            view.sectionHeaderHeight = 0
            view.sectionFooterHeight = 0
            view.contentInsetAdjustmentBehavior = .never
            view.alwaysBounceVertical = true
            view.showsVerticalScrollIndicator = false
            view.showsHorizontalScrollIndicator = false
            view.keyboardDismissMode = .onDrag
            view.accessibilityIdentifier = "comments.list"
            return view
        }

        func attach(
            to view: VideoDetailCommentsTableView,
            scrollAdjustment: VideoDetailScrollAdjustment?
        ) {
            guard !isAttached else { return }
            isAttached = true
            tableView = view
            view.onLayout = { [weak self] in
                self?.scheduleLayoutAdjustment()
            }
            view.register(
                VideoDetailCommentContentCell.self,
                forCellReuseIdentifier: Self.cellReuseIdentifier
            )

            let dataSource = UITableViewDiffableDataSource<Int, Item>(
                tableView: view
            ) { [weak self] tableView, indexPath, item in
                guard let self else { return nil }
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: Self.cellReuseIdentifier,
                    for: indexPath
                )
                if let contentCell = cell as? VideoDetailCommentContentCell {
                    contentCell.configure(
                        rootView: AnyView(self.injectedCellEnvironment(self.cellContent(for: item)))
                    )
                }
                return cell
            }
            self.dataSource = dataSource

            appliedTopInset = max(props.topInset, 0)
            view.contentInset = UIEdgeInsets(
                top: appliedTopInset,
                left: 0,
                bottom: max(props.bottomInset, 0),
                right: 0
            )
            view.contentOffset = CGPoint(x: 0, y: -appliedTopInset)
            view.configureBottomEdgeEffect(
                enabled: props.showsBottomEdgeEffect,
                isActiveContent: props.isActive
            )
            updateAccessibility()

            subscribeToStore()
            refreshSnapshot(reloadData: true)
            lastSelectedSort = props.store.selectedSort

            pendingVirtualOffset = 0
            if let scrollAdjustment, scrollAdjustment.tab == props.tab {
                pendingScrollAdjustment = scrollAdjustment
            }
            scheduleLayoutAdjustment()
        }

        func detach() {
            storeCancellable?.cancel()
            storeCancellable = nil
            tableView?.onLayout = nil
            tableView?.delegate = nil
            isAttached = false
            let scope = suppressionScopeID
            Task {
                await RemoteImageLoadSuppressionGate.shared.setSuppressed(false, for: scope)
            }
        }

        func update(
            props: Props,
            scrollAdjustment: VideoDetailScrollAdjustment?
        ) {
            let layoutChanged = self.props.style != props.style
                || self.props.horizontalPadding != props.horizontalPadding
                || self.props.ownerMID != props.ownerMID
            let activeChanged = self.props.isActive != props.isActive
            // 视频切换会换一个 render store：重订阅并整表刷新。
            let storeChanged = props.store !== self.props.store
            self.props = props
            tableView?.configureBottomEdgeEffect(
                enabled: props.showsBottomEdgeEffect,
                isActiveContent: props.isActive
            )

            if storeChanged {
                if Self.logsHeightDebug {
                    NSLog("CILICILI-HEIGHT clearAll storeChanged")
                }
                cachedRowHeights.removeAll()
                seededHeights.removeAll()
                resubscribeToStore()
                lastSelectedSort = props.store.selectedSort
                lastHeaderSignature = nil
                lastFooterSignature = nil
                refreshSnapshot(reloadData: true)
            }
            if layoutChanged {
                tableView?.reloadData()
            }
            if activeChanged {
                updateAccessibility()
            }
            if let scrollAdjustment,
               scrollAdjustment.tab == props.tab,
               scrollAdjustment.token != lastAdjustmentToken {
                pendingScrollAdjustment = scrollAdjustment
            }
            scheduleLayoutAdjustment()
        }

        // MARK: 数据更新

        private func subscribeToStore() {
            storeCancellable = props.store.$snapshot
                .sink { [weak self] snapshot in
                    Task { @MainActor in
                        self?.trackLoadMoreStateTransition(snapshot.loadMoreState)
                        self?.scheduleSnapshotRefresh()
                    }
                }
        }

        /// 跟踪分页加载态转换：结束后清空游标占用，允许下一次可见触发重试。
        /// 失败只计数供诊断，不做定时退避（对齐 PiliPlus/PiliPod 的静默语义）。
        private func trackLoadMoreStateTransition(_ state: LoadingState) {
            let previous = previousLoadMoreState
            previousLoadMoreState = state
            guard state != previous else { return }
            if state.isLoading {
                return
            }
            if case .failed = state, previous.isLoading {
                consecutiveLoadMoreFailures += 1
                if Self.logsHeightDebug {
                    NSLog("CILICILI-HEIGHT loadMore failed streak=%d", consecutiveLoadMoreFailures)
                }
            } else if state == .loaded, previous.isLoading {
                consecutiveLoadMoreFailures = 0
            }
            requestedLoadMoreToken = nil
        }

        private func resubscribeToStore() {
            storeCancellable?.cancel()
            storeCancellable = nil
            subscribeToStore()
        }

        private func scheduleSnapshotRefresh() {
            guard !refreshScheduled else { return }
            refreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshScheduled = false
                self.refreshSnapshot()
            }
        }

        private func refreshSnapshot(reloadData: Bool = false) {
            guard let dataSource else { return }
            let store = props.store
            let newItemsByID = Self.makeItemsByID(store.commentItems)
            let previousItemsByID = itemsByID
            itemsByID = newItemsByID

            let items = makeItems(store: store, itemsByID: newItemsByID)
            #if DEBUG
            // 仅调试构建记录快照/偏移，便于排查行高与滚动问题。
            PlayerMetricsLog.diagnostic(
                "commentsRefresh items=\(items.count)"
                    + " offset=\(Int(tableView?.contentOffset.y ?? 0))"
                    + " size=\(Int(tableView?.contentSize.height ?? 0))"
                    + " bounds=\(Int(tableView?.bounds.height ?? 0))"
                    + " insetTop=\(Int(tableView?.contentInset.top ?? 0))"
            )
            #endif

            // 新行先离屏量好估算种子（快照刷新在布局路径之外），批量更新时
            // UIKit 的偏移数学全程使用精确值，不会在翻页时扯动可见内容。
            if let tableView, tableView.bounds.width > 10 {
                seedMissingItems(items: items, width: tableView.bounds.width)
            }

            // 结构性行（头部/尾部/错误/空态）内容随加载态变化且只有一行，
            // 逐出缓存让它们重新自适配；评论行高度冻结不动。
            let beforeCount = cachedRowHeights.count
            cachedRowHeights = cachedRowHeights.filter { item, _ in
                if case .comment = item { return true }
                return false
            }
            seededHeights = seededHeights.filter { item, _ in
                if case .comment = item { return true }
                return false
            }
            if Self.logsHeightDebug, cachedRowHeights.count != beforeCount {
                NSLog(
                    "CILICILI-HEIGHT evictedStructural %d -> %d",
                    beforeCount, cachedRowHeights.count
                )
            }

            var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
            snapshot.appendSections([SectionID.main])
            snapshot.appendItems(items)

            if reloadData {
                dataSource.applySnapshotUsingReloadData(snapshot)
            } else {
                dataSource.apply(snapshot, animatingDifferences: false)
                reconfigureChangedItems(
                    items: items,
                    previousItemsByID: previousItemsByID,
                    newItemsByID: newItemsByID,
                    dataSource: dataSource
                )
            }

            if let lastSelectedSort, lastSelectedSort != store.selectedSort {
                // 切换排序后内容整体替换，回到评论区顶部（播放器保持收起）。
                pendingVirtualOffset = max(0, props.topInset - props.minimumPlayerHeight)
                scheduleLayoutAdjustment()
            }
            lastSelectedSort = store.selectedSort

        }

        private func reconfigureChangedItems(
            items: [Item],
            previousItemsByID: [Int: VideoDetailCommentDisplayItem],
            newItemsByID: [Int: VideoDetailCommentDisplayItem],
            dataSource: UITableViewDiffableDataSource<Int, Item>
        ) {
            var reconfiguredItems: [Item] = []
            if !previousItemsByID.isEmpty {
                reconfiguredItems = items.filter { item in
                    guard case .comment(let id) = item,
                          let previous = previousItemsByID[id],
                          let current = newItemsByID[id]
                    else { return false }
                    return previous != current
                }
            }

            let headerSignature = HeaderSignature(
                replyCountText: props.store.replyCountText,
                selectedSort: props.store.selectedSort
            )
            if lastHeaderSignature != nil, lastHeaderSignature != headerSignature {
                reconfiguredItems.append(.header)
            }
            lastHeaderSignature = headerSignature

            let footerSignature = FooterSignature(
                loadMoreState: props.store.loadMoreState,
                hasMoreComments: props.store.hasMoreComments
            )
            if lastFooterSignature != nil,
               lastFooterSignature != footerSignature,
               items.contains(.footer) {
                reconfiguredItems.append(.footer)
            }
            lastFooterSignature = footerSignature

            guard !reconfiguredItems.isEmpty else { return }
            var reconfigureSnapshot = dataSource.snapshot()
            let existingItems = Set(reconfigureSnapshot.itemIdentifiers)
            let targets = reconfiguredItems.filter { existingItems.contains($0) }
            guard !targets.isEmpty else { return }
            // `reconfigureItems` 只重建 cell 内容、不改变 identity，因此行内 @State
            // 会按 `.id(评论 id)` 重置，不会把上一条评论的点赞状态带到复用的 cell 上。
            reconfigureSnapshot.reconfigureItems(targets)
            dataSource.apply(reconfigureSnapshot, animatingDifferences: false)
        }

        /// 按评论 id 去重（服务端极少数情况下会在置顶回复里重复返回），
        /// diffable data source 的同一 section 内不允许重复 item。
        private static func makeItemsByID(
            _ commentItems: [VideoDetailCommentDisplayItem]
        ) -> [Int: VideoDetailCommentDisplayItem] {
            var result: [Int: VideoDetailCommentDisplayItem] = [:]
            result.reserveCapacity(commentItems.count)
            for item in commentItems where result[item.id] == nil {
                result[item.id] = item
            }
            return result
        }

        private func makeItems(
            store: VideoDetailCommentsRenderStore,
            itemsByID: [Int: VideoDetailCommentDisplayItem]
        ) -> [Item] {
            var items: [Item] = [.header]
            let contentState = CommentsSectionContentState(
                store: store,
                shouldShowLoadingPlaceholder: true
            )
            switch contentState {
            case .loading:
                items.append(.loading)
            case .failed(let message):
                items.append(.error(message))
            case .empty:
                items.append(.empty)
            case .reloadPrompt:
                items.append(.error("评论暂时没有返回内容"))
            case .spacer:
                items.append(.spacer)
            case .loaded:
                var seen = Set<Int>()
                seen.reserveCapacity(itemsByID.count)
                for item in store.commentItems where seen.insert(item.id).inserted {
                    items.append(.comment(item.id))
                }
                items.append(.footer)
            }
            return items
        }

        // MARK: Cell 配置

        /// 行内容视图。cell 配置与离屏测高共用同一棵 SwiftUI 树，保证测出的
        /// 理想高度与真实渲染一致。
        @ViewBuilder
        private func cellContent(for item: Item) -> some View {
            let props = props
            switch item {
            case .header:
                CommentsSectionHeaderContent(
                    replyCountText: props.store.replyCountText,
                    selectedSort: props.store.selectedSort,
                    horizontalPadding: props.horizontalPadding,
                    selectCommentSort: props.actions.selectCommentSortAction
                )
                .padding(.top, Self.listTopPadding)
                .padding(.bottom, 10)

            case .loading:
                CommentsSkeletonContent(horizontalPadding: props.horizontalPadding)

            case .error(let message):
                CommentErrorView(
                    message: message,
                    retry: props.actions.retryCommentsAction
                )
                .padding(.horizontal, props.horizontalPadding)

            case .empty:
                EmptyStateView(
                    title: "暂无评论",
                    systemImage: "bubble.left",
                    message: "评论加载后会显示在这里。"
                )
                .padding(.horizontal, props.horizontalPadding)
                .frame(minHeight: emptyStateMinimumHeight, alignment: .center)

            case .spacer:
                Color.clear.frame(height: 1)

            case .comment(let id):
                if let displayItem = itemsByID[id] {
                    let actions = props.actions
                    VStack(spacing: 0) {
                        CommentRow(
                            item: displayItem,
                            style: props.style,
                            showReplies: { actions.showReplies(displayItem.comment) },
                            replyToComment: actions.replyToComment
                        )
                        .equatable()
                        .padding(.horizontal, props.horizontalPadding)

                        Divider()
                            .padding(.horizontal, 14)
                    }
                    .id(displayItem.id)
                } else {
                    Color.clear.frame(height: 1)
                }

            case .footer:
                CommentsTableFooterContent(
                    loadMoreState: props.store.loadMoreState,
                    hasMoreComments: props.store.hasMoreComments,
                    horizontalPadding: props.horizontalPadding,
                    loadMore: props.actions.loadMoreCommentsAction
                )
            }
        }

        /// UIKit 宿主不会继承外层 SwiftUI 环境，
        /// 这里显式补齐评论行依赖的环境对象与自定义环境值。
        private func injectedCellEnvironment(_ content: some View) -> some View {
            let environment = props.cellEnvironment
            return content
                // 固定纵轴尺寸后，内容高度只由自身决定，不受宿主提议高度影响。
                .fixedSize(horizontal: false, vertical: true)
                .environmentObject(environment.dependencies)
                .environmentObject(environment.libraryStore)
                .environment(\.appThemeTintColor, environment.appTintColor)
                .environment(\.commentLikeTarget, environment.commentLikeTarget)
                .environment(\.openAppURLAction, environment.openAppURL)
                .environment(\.commentContentOwnerMID, props.ownerMID)
        }

        private var emptyStateMinimumHeight: CGFloat {
            guard let tableView else { return 0 }
            return max(tableView.bounds.height - props.bottomInset, 0)
        }

        private func updateAccessibility() {
            tableView?.accessibilityElementsHidden = !props.isActive
        }

        // MARK: 布局 / 滚动

        private func scheduleLayoutAdjustment() {
            guard !layoutAdjustmentScheduled else { return }
            layoutAdjustmentScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.layoutAdjustmentScheduled = false
                self.applyLayoutAdjustments()
            }
        }

        private func applyLayoutAdjustments() {
            guard let tableView, tableView.bounds.height > 0 else { return }
            handleWidthChangeIfAny(in: tableView)
            applyTopInsetIfNeeded()
            if let pendingScrollAdjustment {
                self.pendingScrollAdjustment = nil
                lastAdjustmentToken = pendingScrollAdjustment.token
                pendingVirtualOffset = pendingScrollAdjustment.offset
            }
            updateBottomInsetForMinimumContentHeight(in: tableView)
            if let pendingVirtualOffset {
                setVirtualOffset(pendingVirtualOffset)
            }
        }

        /// 宽度变化（首次拿到真实宽度 / 旋转）后所有行高缓存作废，重新自适配。
        private func handleWidthChangeIfAny(in tableView: UITableView) {
            let width = tableView.bounds.width
            guard width > 10, abs(width - lastCachedWidth) > 0.5 else { return }
            lastCachedWidth = width
            if Self.logsHeightDebug {
                NSLog("CILICILI-HEIGHT clearAll width=%.1f", width)
            }
            cachedRowHeights.removeAll()
            seededHeights.removeAll()
            tableView.reloadData()
        }

        /// 内容不足一屏时补足底部留白，保证播放器仍可随滚动完全收起
        /// （等价于旧实现的 `scrollContentMinimumHeight`）。
        private func updateBottomInsetForMinimumContentHeight(in tableView: UITableView) {
            let baseBottomInset = max(props.bottomInset, 0)
            let minimumContentExtent = max(
                tableView.bounds.height - props.minimumPlayerHeight,
                0
            )
            let extraBottomInset = max(
                0,
                minimumContentExtent - tableView.contentSize.height - baseBottomInset
            )
            let targetBottomInset = baseBottomInset + extraBottomInset
            guard abs(tableView.contentInset.bottom - targetBottomInset) > 0.5 else {
                return
            }
            var inset = tableView.contentInset
            inset.bottom = targetBottomInset
            if Self.logsHeightDebug {
                NSLog(
                    "CILICILI-HEIGHT inset.bottom %.1f -> %.1f size=%.1f bounds=%.1f",
                    tableView.contentInset.bottom, targetBottomInset,
                    tableView.contentSize.height, tableView.bounds.height
                )
            }
            tableView.contentInset = inset
            tableView.verticalScrollIndicatorInsets.bottom = baseBottomInset
        }

        private func applyTopInsetIfNeeded() {
            guard let tableView else { return }
            let newTopInset = max(props.topInset, 0)
            guard abs(newTopInset - appliedTopInset) > 0.5 else { return }
            appliedTopInset = newTopInset
            tableView.contentInset.top = newTopInset
            setVirtualOffset(max(0, lastReportedVirtualOffset ?? 0))
        }

        /// 以“虚拟偏移”定位：0 = 播放器展开、内容顶到留白下方。
        private func setVirtualOffset(_ offset: CGFloat) {
            guard let tableView else { return }
            guard tableView.bounds.height > 0 else {
                pendingVirtualOffset = offset
                return
            }
            let minY = -tableView.contentInset.top
            let maxY = max(
                minY,
                tableView.contentSize.height
                    + tableView.contentInset.bottom
                    - tableView.bounds.height
            )
            let targetY = offset - tableView.contentInset.top
            guard targetY <= maxY + 0.5 else {
                // 内容还没测量完/底部留白未补齐，等下一次布局再定位。
                pendingVirtualOffset = offset
                return
            }
            pendingVirtualOffset = nil
            let clampedY = min(max(targetY, minY), maxY)
            guard abs(tableView.contentOffset.y - clampedY) > 0.5 else { return }
            tableView.setContentOffset(
                CGPoint(x: tableView.contentOffset.x, y: clampedY),
                animated: false
            )
        }

        private func reportScrollOffset(in scrollView: UIScrollView) {
            let virtualOffset = max(0, scrollView.contentOffset.y + scrollView.contentInset.top)
            if let lastReportedVirtualOffset,
               abs(lastReportedVirtualOffset - virtualOffset) <= 0.5 {
                return
            }
            lastReportedVirtualOffset = virtualOffset
            props.onScrollOffsetChange?(props.tab, virtualOffset)
        }

        private func reportPhase(_ phase: ScrollPhase) {
            guard phase != lastPhase else { return }
            lastPhase = phase
            props.onScrollPhaseChange?(props.tab, phase)
            let isSuppressed = FastScrollImageLoadSuppressionPolicy.suppressesNetworkLoads(phase: phase)
            let scope = suppressionScopeID
            Task {
                await RemoteImageLoadSuppressionGate.shared.setSuppressed(isSuppressed, for: scope)
            }
        }

        // MARK: 分页

        private func isLoadMoreFailed(_ state: LoadingState) -> Bool {
            if case .failed = state { return true }
            return false
        }

        private func requestLoadMorePage() {
            let store = props.store
            guard !store.loadMoreState.isLoading else { return }
            // 以“已加载条数”作为页令牌：同一条数只发一次，成功/失败后清空，
            // 下一次 footer 可见即可自然重试。
            let token = store.comments.count
            guard requestedLoadMoreToken != token else { return }
            requestedLoadMoreToken = token
            if Self.logsHeightDebug {
                NSLog("CILICILI-HEIGHT loadMoreRequest count=%d", token)
            }
            props.actions.loadMoreCommentsAction()
        }

        // MARK: UITableViewDelegate（UIScrollViewDelegate）

        // 行高来源（确定性递进）：显示捕获的冻结值 → 离屏精确种子 → 兜底自适配。
        // cell 同步换 rootView，显式高度下不会再出现"量到上一份内容"的竞态。
        func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            guard let item = dataSource?.itemIdentifier(for: indexPath) else {
                return UITableView.automaticDimension
            }
            if let cachedHeight = cachedRowHeights[item] {
                return cachedHeight
            }
            return seededHeights[item] ?? UITableView.automaticDimension
        }

        func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
            // 只读预计算字典，绝不在布局路径里同步跑 SwiftUI 测量
            // （会与 cell 的 hosting 布局互相干扰，出现 0×0 空壳内容）。
            guard let item = dataSource?.itemIdentifier(for: indexPath) else {
                return Self.defaultEstimatedRowHeight
            }
            return cachedRowHeights[item]
                ?? seededHeights[item]
                ?? Self.defaultEstimatedRowHeight
        }

        func tableView(
            _ tableView: UITableView,
            willDisplay cell: UITableViewCell,
            forRowAt indexPath: IndexPath
        ) {
            guard let item = dataSource?.itemIdentifier(for: indexPath) else { return }
            if case .footer = item {
                // footer 即将显示 = 到达列表末尾，触发下一页（PiliPod 的 footer
                // onAppear 同款触发点）。守卫在 requestLoadMorePage 内。
                requestLoadMorePage()
            }
            let height = cell.frame.height
            guard height > 1 else { return }
            // 记录真实显示高度供估算使用。绝不能在这里做 begin/endUpdates
            // 之类的表几何操作——willDisplay 处于布局过程中，重入会崩溃并抖动。
            if let previousHeight = cachedRowHeights[item],
               Self.logsHeightDebug, case .comment(let id) = item,
               abs(previousHeight - height) > 0.5 {
                NSLog(
                    "CILICILI-HEIGHT changed id=%d cached=%.1f now=%.1f",
                    id, previousHeight, height
                )
            }
            cachedRowHeights[item] = height
        }

        /// 离屏测量行高作为估算种子。只在快照刷新等布局路径之外调用。
        /// 提议高度用 0：整行回复按钮的 `maxHeight: .infinity` 弹性占位在提议
        /// 0 时收敛为 0，ZStack 高度恰好等于内容理想高度；提议无限会被撑爆。
        private func seedMissingItems(items: [Item], width: CGFloat) {
            guard width > 10 else { return }
            for item in items where seededHeights[item] == nil {
                sizingHostController.rootView = AnyView(
                    injectedCellEnvironment(cellContent(for: item))
                        .frame(width: width, alignment: .topLeading)
                )
                let fittingSize = sizingHostController.sizeThatFits(
                    in: CGSize(width: width, height: 0)
                )
                seededHeights[item] = max(fittingSize.height.rounded(.up), 1)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportScrollOffset(in: scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            reportPhase(.tracking)
        }

        func scrollViewDidEndDragging(
            _ scrollView: UIScrollView,
            willDecelerate decelerate: Bool
        ) {
            reportPhase(decelerate ? .decelerating : .idle)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            reportPhase(.idle)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            reportPhase(.idle)
        }
    }
}

// MARK: - 行内容

/// 列表里的分页尾部：加载中 / 失败重试 / 继续下滑 / 到底。
/// 自动续载由列表的滚动阈值驱动，这里仅保留点按兜底。
private struct CommentsTableFooterContent: View {
    let loadMoreState: LoadingState
    let hasMoreComments: Bool
    let horizontalPadding: CGFloat
    let loadMore: () -> Void

    private var isFailed: Bool {
        if case .failed = loadMoreState { return true }
        return false
    }

    var body: some View {
        Group {
            if loadMoreState.isLoading {
                InlineLoadingStateView(title: "正在加载评论")
            } else if hasMoreComments || isFailed {
                // 失败不进红字错误态（对齐 PiliPlus/PiliPod 的静默语义）：
                // 保持中性文案，继续下滑或点按都会自然重试。
                Text("继续下滑加载更多评论")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: loadMore)
                    .accessibilityIdentifier("comments.loadMore")
            } else {
                Text("没有更多评论了")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 8)
    }
}
