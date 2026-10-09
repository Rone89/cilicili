# 清晰度切换画面交接修复

## 原因

当前视频清晰度切换通常创建新播放器，而不是在同一个 HLS 多画质实例中切换。共享 Surface 换绑时旧 drawable 被移除，新实例尚未输出首帧。已有 `beginPlaybackTransition` 保存旧画面，但详情页宿主没有显示 `transitionSnapshot`，因此这段空档可见黑底。这一缺口也存在于旋转实验之前的路径。

## 实现

- 在 `VideoDetailShellSurfaceHost` 中增加非交互 UIImageView，位于视频 drawable 上方、控件和弹幕下方。
- 订阅 `VideoDetailPlayerIdentityRenderStore` 的快照发布。安装新播放器时现有同步发布发生在换绑之前，旧帧可先覆盖 drawable。
- 尺寸约束沿用宿主边界；视频帧使用当前 gravity，包含容器尺寸的截图保持 aspect-fit。
- 继续使用现有首帧回调、220ms 释放等待和 6s 安全释放。没有新增定时器、旋转时序、播放引擎或独立动画。
- 无有效快照时隐藏，退出宿主时解除订阅、清空图片；实验开启和关闭两种宿主都适用。
- 不修改页面布局、控件、手势、画质请求、缓存、缓冲或 PiP 策略。

## 验证

Validated with Xcode 27.1（27A9269）。scheme `bili`，Debug，destination `cilicili-iOS27-Codex`（iOS 27 Simulator），部署目标仍为 iOS 26.1。

- Debug build：PASS。两条已有 warning 位于 RootTabFixtureURLProtocol 和 IncomingMessageBubbleShape，本次没有改动对应文件。
- `VideoDetailSurfaceHostTests` + `VideoDetailPlaybackDiagnosticsTests`：14 PASS，0 FAIL，0 SKIP。
- 新增测试覆盖同步遮挡先于换绑、两条宿主路径、横屏/竖屏收缩几何、gravity、缺失图片、清理解除订阅，以及连续替换时旧首帧回调与待释放任务的隔离。
- 原有本地 H.264 Surface 测试通过 20 轮几何循环，播放器、item、Surface 身份与绑定保持稳定。这不是系统方向旋转测试。
- 首帧释放测试注入现有回调与已捕获快照阶段，没有篡改播放器私有 readiness，也不代表真实网络解码时序验证。

## 限制

这是填补换绑画面空档，不是消除网络准备和解码耗时；等待期间显示静止旧帧。如果捕获不到有效旧帧，则保留现有加载行为。安全超时仍会撤下遮罩，避免长期停留旧图。

本轮没有真机播放、HDR 色彩、PiP、实际黑帧时长或主线程耗时测量，相关指标 unavailable。需要在 iPhone 上继续验证播放/暂停、快速连续切换、不同视频比例及 HDR 画质的交接观感。
