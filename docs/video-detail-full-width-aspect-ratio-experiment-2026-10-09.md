# 视频原比例全宽与收缩实验

## 修正后的范围

用户最终确认：手机竖屏时，仅对比 16:9 更高、但高度不超过宽度的画面启用原比例全宽窗口。因此范围是 `1 ≤ width / height < 16/9`，包括 1:1、4:3、3:2，不包括宽小于高的竖向视频。

入口：我的 → 开发者与诊断 → 实验开关 →「视频原比例全宽与收缩」。默认关闭，每次打开详情页时读取；保留初版实验的 UserDefaults key，使手机上已保存的开关继续有效。不需要重新登录。

## 行为

- 默认播放器窗口宽度为页面宽度，高度为 `页面宽度 / 视频宽高比`。例如屏幕宽度 390pt，4:3 的窗口为 390×292.5pt，3:2 为 390×260pt，1:1 为 390×390pt。
- 上滑复用现有 UIScrollView 的交互收缩。播放、暂停、Seek 时的最小窗口均为全宽 16:9（沿用现有高度像素对齐 token）。回到顶部重新展开。
- 内容留白、滚动收缩距离、弹幕展开画布采用相同规则；简介／评论切换保留已有阅读位置。
- 视频继续使用原 aspect-fit，不拉伸、不新增裁剪规则。不重建 Surface，不修改播放器和旋转时序。
- 宽高比小于 1 的竖向视频、16:9 及更宽画面、横屏全屏和竖屏全屏均保持实验关闭时的原行为。
- 清除初版为极窄竖向视频引入的 metadata 例外。关闭时沿用原判定和布局，包含原有暂停收缩至 54pt 的规则。

## 实现范围

LibraryStore、MineDeveloperDiagnosticsView、VideoDetailInitialVideoGeometry、VideoDetailShellLayout、VideoDetailSwiftUIContainer、PlaybackDetailSharedLayoutTests；未改 HLS Bridge、播放引擎、详情页工具栏或其他页面布局。

## 验证方式

Xcode 27.1，scheme `bili`，Debug，`cilicili-iOS27-Codex`（iOS 27 Simulator），部署目标仍为 iOS 26.1。

测试覆盖默认关闭、旧 key 持久化保持、1:1／4:3／3:2 展开尺寸及收缩下限、内容滚动距离、固定弹幕画布、播放与暂停相同下限、竖向及宽屏规则不变、全屏几何不变、Tab 阅读位置、开关按页面捕获和关闭恢复旧布局。

实际 SwiftUI 容器集成测试在 UIWindow 中分别挂载 1:1、4:3、3:2 页面，驱动现有 UIScrollView 的公开拖动 delegate 生命周期及 contentOffset，验证收缩到 16:9 并回顶部展开。这是组件集成测试，不能替代真机播放或手指手势验证。

验证结果：`PlaybackDetailSharedLayoutTests` 和 `VideoDetailSurfaceHostTests` 共 52 项通过，0 失败、0 跳过；Debug 模拟器编译通过。本次修正版尚未进行真机播放验证。
