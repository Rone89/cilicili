# 竖屏视频全宽与收缩实验

## 行为

入口：我的 → 开发者与诊断 → 实验开关 →「竖屏视频全宽与收缩」。独立开关，默认关闭，保存在 LibraryStore；每个详情页打开时读取，下次打开页面生效。

开启时，仅调整普通竖屏布局中的有效宽高比 `0 < width / height < 1` 的视频：

- 默认播放器窗口宽度为页面宽度，高度为 `页面宽度 / 视频宽高比`，不再沿用 65% / 72% 屏幕高度限制。
- 上滑复用已有 UIScrollView 的交互收缩；播放、暂停、Seek 状态下的最小窗口均为页面全宽的 16:9（高度沿用现有像素对齐 token）。
- 回到顶部恢复完整展开；简介／评论切换复用已有阅读位置保持。
- 内容留白、最小可滚动距离和弹幕的展开画布使用相同几何规则，收缩时不重建 Surface 或播放器。
- 不改变画面 gravity，继续按现有 aspect-fit 展示，不拉伸视频或新增裁剪规则。

宽高比等于或大于 1、横屏全屏和竖屏全屏沿用原规则。关闭时原来的 0.9 判定、屏幕高度上限及暂停收缩至 54pt 全部保留。为了覆盖宽小于高的有效视频，实验开启时也接受原 metadata helper 排除的极窄正比例；未开启的调用保留原过滤规则。

超长视频的自然展开高度可能超过可视区域；本实验遵循全宽比例，不额外增加高度上限。极端比例的真机可见区域和手势可达性仍需验证。视频尺寸尚未获取时仍使用原有默认比例占位。

## 实现范围

LibraryStore、MineDeveloperDiagnosticsView、VideoDetailInitialVideoGeometry、VideoDetailShellLayout、VideoDetailSwiftUIContainer；没有修改旋转完成时序、HLS Bridge、播放引擎、详情页工具栏或其他页面布局。

## 验证

Xcode 27.1，scheme `bili`，Debug，`cilicili-iOS27-Codex`（iOS 27 Simulator），部署目标仍为 iOS 26.1。

新增 XCTest 覆盖：默认关闭和持久化、9:16／3:4／接近方形／极窄比例、播放与暂停共用下限、内容滚动距离、固定弹幕画布、全屏与横屏规则不变、Tab 阅读位置、开关按页面捕获、关闭恢复旧布局。

实际 SwiftUI 容器集成测试挂入 UIWindow，驱动现有 UIScrollView 的公开拖动 delegate 生命周期和 contentOffset，验证收缩到 16:9 并回到顶部展开。这是组件集成测试，不是 XCUITest 手指手势或真机播放验证。

初轮原有 Surface 20 次几何循环测试在兼容路径出现一次异步图层尺寸未及时完成，单独复测通过；没有为此更改生产时序或放宽原断言。

最终 `PlaybackDetailSharedLayoutTests` + `VideoDetailSurfaceHostTests`：52 PASS、0 FAIL、0 SKIP，包括 6 个新增实验测试。结果：`test_sim_2026-10-09T03-55-40-564Z_pid116_b7e7c630.xcresult`。构建保留仓库既有并发及未使用变量警告，修改文件无新增 warning。
