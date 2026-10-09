# 视频详情布局转正与导航清理

## 当前行为

- 用户个人页 `UploaderView` 显式使用 `.toolbar(.hidden, for: .tabBar)`，原生返回或侧滑返回恢复一级页 TabBar。
- UIKit 视频层与旋转稳定性优化成为默认路径。删除实验设置、持久化读取/写入、旧 SwiftUI surface-only Hosting、host factory 和仅为双路径存在的协议。视频详情直接持有 `DirectUIKitPlayerSurfaceHostView`，始终使用已验证的同步 bounds refresh。
- 直播仍使用原有 `UIKitPlayerSurfaceHostView`。保留视频详情旋转预热、恢复、watchdog、控件与弹幕的 SwiftUI overlay，以及清晰度切换的旧帧保护。
- 视频原比例全宽与收缩成为默认行为。范围继续为 `1:1 ≤ width/height < 16:9`；手机竖屏时按页面宽度展开，上滑最小收缩至全宽 16:9，播放和暂停一致。其他比例及全屏布局规则不变。
- 首次加载占位页采用相同的原比例判定，避免进入正式页时窗口高度跳变；其他比例沿用原占位页尺寸规则。
- 旧实验 key 已不再读取；历史关闭值不会关闭转正功能。不修改或清空用户持久化数据。
- 移除加载页和正式播放器顶部返回按钮、三个专用组件及多余回调传递。保留底部返回、侧滑导航、收缩栏和全屏切换入口。

## 验证

Xcode 27.1，scheme `bili`，Debug，`cilicili-iOS27-Codex`（iOS 27.0 Simulator）。部署目标仍为 iOS 26.1。

- PASS：Debug build 和模拟器启动。
- PASS：`PlaybackDetailSharedLayoutTests`、`VideoDetailSurfaceHostTests` 共 49 项测试，0 失败。删除仅覆盖退役开关和旧 factory 的三项测试，保留并更新实际行为回归测试。
- PASS：本地媒体 20 次尺寸往返/40 次几何更新，Surface、AVPlayer、AVPlayerItem identity 稳定，无额外 attach/detach；布局同步、seek/播放/暂停、解绑释放、清晰度切换覆盖与过期首帧回调测试通过。
- PASS：真实 SwiftUI 容器在 UIWindow 中挂载 1:1、4:3、3:2，驱动 UIScrollView 公开 delegate 验证收缩至 16:9、回顶展开、内容阅读位置与弹幕画布。
- PASS：个人页原生返回按钮及侧滑返回两个 XCUITest，TabBar 在个人页隐藏、返回后恢复。
- FAIL / 未完成：真实网络视频全屏往返 XCUITest 在等待 `ui.player.fullscreen.toggle` 时失败，尚未进入旋转流程。另行启动后截图显示页面停在“正在加载”；公开视频信息 API 探测返回 HTTP 412。未改为跳过或宣称通过。
- 未验证：本轮真机视频播放、全屏往返和可见黑帧。组件几何测试不能替代真机旋转验收。
- 构建有原有并发隔离/捕获等 warning；本次改动文件无新增编译 warning/error。`git diff --check` 通过。
