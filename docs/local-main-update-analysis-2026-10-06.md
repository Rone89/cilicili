# 本地 main 与 GitHub 最新版本差异分析

核对日期：2026-10-06（北京时间）。依据为更新后的远端引用、GitHub Release API、提交记录和最终代码差异。本次未运行 App、构建或性能测试；文案描述代码中的功能与修复，不承诺量化性能提升。

## 对比范围

| 对象 | 版本 / 提交 | 与本地 main 的差异 |
| --- | --- | --- |
| 本地 main | 1.1，Build 1；`c809bf06f3a0598991dad467d6942a70510bfcfd` | 本次分析目标 |
| GitHub 最新 main | `c61b0d33966c5d8e87ea20527b8ba48c702c10c1`，2026-09-15 | 本地领先 57 个提交；318 个文件变化，新增 21,138 行、删除 5,074 行 |
| GitHub 最新正式 Release | v1.0.23，Build 473；`9ba88cddcefbfba3b8007768eee86e1eb1437e95` | 本地领先 60 个提交；323 个文件变化，新增 21,310 行、删除 5,081 行 |

最新发布包见 [v1.0.23](https://github.com/Rone89/cilicili/releases/tag/v1.0.23)，发布时间为北京时间 2026-09-15 02:03。远端 main 在该版本之后合入了 [稍后再看](https://github.com/Rone89/cilicili/commit/c61b0d33966c5d8e87ea20527b8ba48c702c10c1)。因此，“稍后再看”属于从发布包升级时新增的功能，不属于本地相对最新远端 main 的独有变化。

## 用户能感受到的主要变化

| 变化 | 用户实际看到的行为 | 核对依据 |
| --- | --- | --- |
| 我的页搜索与设置分组 | 用关键词查找账号、画质、缓存等入口；日常体验、内容与隐私、存储与诊断分组；缓存清理有单独入口 | `8680293`、`10ec2ce`、`448fa76`；MineSearchCatalog、MineContentView、MineSettingsSection、ResourceCacheManagementView |
| 多账号正式开放 | 不再受旧实验开关限制；账号信息菜单可直接切换主账号、进入账号管理 | `448fa76`；LibraryStore、MineAccountSection |
| 视频页返回历史 | 底部返回入口支持单击返回上一页、长按选择此前的导航页面；不是新增观看记录功能 | `71a649b`、`dc6f689`、`448fa76`；NavigationHistory、VideoDetailHistoryBackMenu |
| UP 主头像菜单 | 头像菜单提供个人空间和关注操作；已关注状态使用主题色边框 | `103204c`；VideoDetailActionStripOwnerMenu |
| 搜索位置保留 | 视频返回后恢复滚动位置；关键词、分类和排序变化时重置到顶部 | `e7ceaee`；SearchListView |
| 倍速、拖进度和页面退出修复 | 临时倍速使用独立路径；拖进度后结合真实视频帧推进判断画面恢复；离开视频页立即暂停，在导航过渡结束后完成资源收尾 | `ce9f423`、`c05741e`、`5f17fcb`、`a232b48`、`b727a53`、`4278784`、`6fa23f3`；PlayerSpeedBoostModel、PlayerStateViewModel、UserSeekRevealSettling、VideoDetailPlaybackNavigationStopActions |
| 播放请求与线路处理 | 共享视频分段请求、取消无用候选请求，避免不同线路的健康评分互相干扰；蜂窝网络下优先使用符合域名规则的 B 站线路，兼容处理成为常规逻辑 | `ab5f9bf`、`448fa76`；VideoRangeSharedFetch、AVPlayerHLSBridgeEngine、CellularBiliTrafficCompatibility；不能据此承诺免流 |
| 常规弹幕改造 | 使用 DanmakuKit；显示区域支持百分比调整；增加弹幕类型开关、轨道高度、上下留白和允许重叠的海量弹幕选项 | `0c90d73` 等；DanmakuService、VideoDetailDanmakuSettingsSheetContent、DanmakuKitOverlayView |
| Metal 弹幕实验 | 增加 GPU 绘制方案；适配显示刷新率、减少重复绘制，并修复时钟校正和窗口切换中的位置问题 | `8b16e80` 至 `6890a27`；MetalDanmakuRenderer、MetalDanmakuView、MineDeveloperDiagnosticsView；最终仍为默认关闭的实验，图片表情暂以文字显示 |
| 评论交互调整 | “长按评论显示操作”启用后，轻点不再打开回复输入框，长按提供复制、回复；旧偏好键继续使用，新安装默认关闭 | `3ccf475` 等；CommentCopySupport、DynamicCommentRow、VideoDetailCommentRow、MineDisplaySettingsSection |
| 图文与多图布局 | 动态、评论组图根据数量和容器宽度自适应；统一文字行高、表情对齐并处理边界空白；图片阴影可开关 | `c0d66d2`、`e680046`、`76b8777`、`dc6f689`；DynamicAdaptiveImageGrid、CompactDynamicImageMosaicGrid、DynamicAttributedTextInput、BiliModels |
| 统一界面与加载样式 | 普通或液态玻璃操作按钮可选；页面边距、操作栏、进度条更统一；首页只保留系统下拉刷新；直播列表短期缓存先展示再刷新 | `298b30a`、`0f1dcc7`、`10ec2ce`、`1a2c71e`、`28161c6`、`bb80fcc`、`011f22b`；HomeFeedScrollView、VideoDetailActionStrip、LiveFeedWarmCache、LiveViewModel |

## 文案筛选

- ResourceLoader manifest 播放实验曾加入，后来在 `61c1097` 撤掉，最终版本不列为新增功能。
- 视频详情赞助标记曾加入，后来在 `e7ceaee` 撤掉，最终版本不列为新增功能。
- Metal 弹幕保留实验性质，不写成默认启用的正式方案，也不宣称已验证的省电、帧率或速度提升。
- 字号、画中画、听视频、内容过滤等已有功能主要是入口或组织变化，不重复写成全新功能。
- 大量性能日志、诊断、测试和内部重构已合并或省略，避免把提交数量误当成用户功能数量。
- 原先的自定义下拉刷新及距离设置已移除，首页统一使用系统刷新，不继续宣传旧选项。

## 从 1.0.23 发布包升级时的补充文案

- **“稍后再看”有入口了。** 在“我的”页可以打开账号的稍后再看列表，查看之前暂存的视频。

相对最新远端 main 的可直接使用文案保存在项目根目录的 `RELEASE_NOTES_1.1.md`；发布面向 1.0.23 用户的说明时，可加上以上补充条目。
