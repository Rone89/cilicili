# AI 字幕实验

状态：实验性功能，默认关闭。开关位于「我的 → 开发者与诊断 → 实验开关 → AI 字幕实验」。开关在**下次进入视频详情**时生效，不热更新当前页面。

## 功能范围

- 解析播放详情接口 `/x/player/wbi/v2`（WBI 签名 + 登录 Cookie）返回的 `subtitle.subtitles[]` 字幕轨列表；`type == 1` 为 AI 生成轨（对齐 PiliPlus 的判定），`lan_doc` 显示名带"（AI）"后缀。
- 字幕内容从轨的 `subtitle_url` / `subtitle_url_v2` 下载 JSON（`body[]` 的 from/to/content），统一升级 https。
- 渲染：播放器底部 overlay，时间驱动复用 `PlayerPlaybackClock`（0.2s 节流发布），二分查找当前 cue。
- 轨选择入口：弹幕设置 sheet / 横屏弹幕设置页顶部新增「字幕（实验）」区块（仅在拉到字幕轨后出现），支持 关闭 / 各字幕轨 切换。
- 默认轨优先级：中文 CC > 中文 AI > 第一条轨。

## 实现位置

- 实验开关：`LibraryStore.aiSubtitleExperimentEnabled`（key `cc.bili.experimental.aiSubtitle.v1`）
- API：`BiliAPIClient+VideoSubtitles.swift`（轨列表 + cue 下载）
- 状态：`VideoDetailSubtitleStore`（挂 `VideoDetailViewModelRenderStores.subtitle`）
- 动作：`VideoDetailSubtitleActions.swift`（VM 扩展：加载轨/选轨/时间更新）
- 渲染层：`VideoDetailPlayerSurfaceSubtitleLayer.swift`，挂载于 `VideoDetailShellSurfaceHost` 弹幕层旁（zIndex 2.55，`allowsHitTesting(false)`）
- 设置区块：`VideoDetailDanmakuSettingsSheetContent` 新增可选参数 `subtitleStore` / `onSelectSubtitleTrack`

## 已知限制

- AI 字幕轨由 B 站服务端按视频/账号下发，并非所有视频都有；未登录或纯 Cookie 会话可能拿不到 AI 轨。
- 开关切换不热更新当前视频，需重新进入详情页。
- 字幕渲染不做样式自定义（固定字号/样式），不进竖屏"更多"面板的独立入口（复用弹幕设置页）。
- cue 时间精度受时钟 0.2s 节流限制，切换误差在 0.2s 内。
- 未做单元测试覆盖（实验阶段），验收以真机为准。

## 真机验收步骤

1. 打开「AI 字幕实验」开关，进入一个明确有 AI 字幕的视频（播放器 CC 字幕按钮可见或官方 App 显示 AI 字幕）。
2. 弹幕设置 → 「字幕（实验）」区块应出现字幕轨列表，默认选中中文轨。
3. 播放至有语音处，底部应出现字幕文本，随语音变化。
4. 切换 关闭 / 其他轨 / 再切回，观察渲染与消失行为。
5. 关闭实验开关后重新进入视频详情，字幕应完全不出现（也不请求字幕接口）。
