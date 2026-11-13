# Ibili「封面清晰度」功能实现分析（2026-11-13）

分析对象：`/Users/rayc/Desktop/ibili-review/Ibili`（SwiftUI + Rust core 的 B 站客户端）。
结论先行：Ibili 的封面清晰度 = **两件事的组合**——(1) 封面 URL 永远按"卡片在屏幕上的真实物理像素"裁剪请求；(2) 用户可再叠加一个 CDN 压缩质量参数 `q`（60/75/90/100 或不传）。实现全部在 iOS 侧，约 100 行核心代码，Rust core 不参与。

## 1. 设置入口（SettingsView.swift:13-105）

- Picker「封面清晰度」，绑定 `$settings.imageQualityRaw`。
- 选项：`自动（按显示像素）=0 / 流畅 60 / 标准 75 / 高清 90 / 原图 100`。
- Footer 文案：自动模式按列数与屏幕像素密度选择最优分辨率，仅下载所需像素。
- 0 = 自动，即 **不传 q 参数**，由 CDN 决定该尺寸下的默认压缩质量。

## 2. 设置持久化（AppSettings.swift:185, 390-393）

```swift
@AppStorage("ibili.feed.imageQuality") var imageQualityRaw: Int = 0

func resolvedImageQuality() -> Int? {
    imageQualityRaw <= 0 ? nil : imageQualityRaw   // nil = 只带尺寸不带 q
}
```

## 3. 设置 → 渲染模型的传递

- 首页/搜索等视图读 `settings.resolvedImageQuality()`，塞进 `MediaCardRenderModel.imageQuality: Int?`（FeedRenderModels.swift:62）。
- 同时把它作为 `contentVersion: AnyHashable(...)`（HomeView.swift:423），设置一变整个网格重建配置，封面立刻换清晰度。
- 预取：`CoverImagePrefetcher.shared.prefetch(covers, targetPointSize: 卡片实际尺寸, quality:)`（HomeView.swift:508-520）。
- 组件默认值：视频卡 nil（跟随设置），PGC 海报卡回退 82，紧凑行 75。

## 4. 核心 URL 变换（Bridge/BiliImageURL.swift，全部逻辑所在）

B 站 CDN（`i*.hdslb.com`）支持 URL 后缀：`<src>@<宽>w_<高>h_<q>q.webp`，尺寸与 q 均可省略。

```swift
static func resized(_ src: String, pointSize: CGSize, quality: Int? = nil) -> String {
    // 1. 协议归一化：// → https:，http → https
    // 2. scale = max(UIScreen.main.scale, 2.0)
    //    w = pointSize.width × scale（物理像素），h 同理
    // 3. 正则剥掉已有 @ 后缀：@(?:\d+[a-z]_?)+(?:\.[a-zA-Z0-9]+)?$
    //    （注释自述等价于 PiliPlus 的 _thumbRegex，即参考 PiliPlus 实现）
    // 4. 拼 "@{w}w_{h}h"，quality>0 时再拼 "_{q}q"，末尾 ".webp"，保留原 query
}
```

安全护栏（`canAppendResizeSuffix`）：只有 host 以 `hdslb.com` 结尾且路径以 .jpg/.jpeg/.png/.webp 结尾才追加后缀，其他 URL 原样返回。另有 `original()` 剥掉全部后缀取原图。

关键设计：**尺寸永远是"按显示像素"自动算的**（点尺寸 × scale，不留给用户选）；用户设置的清晰度只影响 CDN 压缩等级 q。自动档 = 只发 `@w_w_h.webp` 不带 q。

## 5. 尺寸从哪来（MediaCardContentView.swift:302-345）

- 卡片 `configure(item:targetWidth:)` 由网格列数决定宽度；封面目标尺寸 = `(targetWidth, targetWidth / coverAspectRatio)`，交给 `BiliImageURL.resized`。
- `traitCollectionDidChange`（深色模式切换）会按同尺寸重载。

## 6. 缓存与解码管线（配合清晰度不重复下载）

- `ImageRequestKey(url, maxPixelDimension)`：缓存键 = URL + `#pixels=上限`，同 URL 不同清晰度各存一份。
- `ImagePipeline.displayPixelDimension(for:)`：`min(max(点尺寸×scale, 160), 屏幕物理像素)`，作为解码降采样上限。
- 请求合并：`ImagePipeline` 对相同 key 的并发请求只发一次网络（waiters 等待者机制），取消独立。
- 内存缓存 `ImageCache`（SharedViews.swift:6）按 URL+pixels 键存。
- 磁盘缓存 `ImageDiskCache`：LRU 淘汰，默认上限 256MB（可调，≥16MB），单文件写入限 max(上限/8, 4MB)；读取后在解码阶段按 maxPixelDimension 降采样（ImagePipeline.swift:76）。
- 顺序：内存 → 磁盘+降采样解码 → 网络（重试 3 次）。

## 7. 与 ccswift 现状对比

ccswift 已有 `RemoteImageQualityPreference`（bili/Sources/Utilities/PerformanceServices.swift:4556，自动/省流/均衡/高清），思路不同：

| | Ibili | ccswift |
|---|---|---|
| 请求尺寸 | 永远 = 卡片显示物理像素（点×scale） | 固定档位（封面默认 480×270 / 672×378，大图 maxSide 1280），`coverThumbnailURL(fitting:)` 部分场景可算 |
| 清晰度调节手段 | CDN 压缩参数 `_q`（60/75/90/100） | 只调"最大边长像素上限"（560/960/1280/2600 或按网络/省电/发热动态降） |
| 自动档语义 | 不传 q，CDN 默认压缩 | Wi-Fi 1280、蜂窝 760、低电量/发热 640 |
| URL 变换点 | `BiliImageURL.resized` 统一入口 | `biliImageView2URL`（BiliModels.swift:7089 附近） |

即 ccswift 的"清晰度"是通过**降分辨率**实现的，没有向 CDN 传显式压缩质量；同一像素尺寸下清晰度档次无法进一步拉开。若要引入 Ibili 式封面清晰度，最小改动路径：

1. 给 `biliImageView2URL` 增加可选 `quality: Int?` 参数，拼 `_q` 段（B 站语义相同，host 判断 ccswift 已有）。
2. 设置页加「封面清晰度」Picker（自动/60/75/90/100），存 UserDefaults，读取处 nil 化。
3. 传递点：卡片渲染模型携带 quality + 作为内容版本号触发重载（参照 HomeView.swift:423 的做法）。
4. 缓存键需包含 quality（ccswift 现有键基于 URL，URL 里带 q 自然区分，无需改键）。

## 8. 可复用细节

- `displayPixelDimension` 的 160px 下限与屏幕上限夹取。
- "设置变更 → contentVersion → 网格重配置"的失效技巧。
- hdslb host + 图片扩展名的护栏判断（防第三方图床 URL 被误改）。
- 预取时用与卡片渲染完全相同的 targetPointSize + quality，保证预取的 URL 与正式加载的 URL 一致从而命中缓存。

## 9. 落地结果与更正（Build 155–156）

**更正第 7 节一处不准确表述**：ccswift 的视频封面其实早已"贴屏"。首页/动态/紧凑卡片/故事媒体等所有视频封面都经 `AdaptiveVideoCoverImage`（DesignSystem）渲染，它用 `GeometryReader` 量出卡片真实渲染尺寸（或 fixedSize）× `displayScale`，走 `biliCoverThumbnailURL(fitting:scale:maximumPixelLength:)` 按像素要图，与 Ibili 同思路。第 7 节表格里"固定档位 480×270"只是 `VideoCardDisplayModel.coverURL` 的兜底备用值，并非实际渲染路径。因此"Ibili 尺寸贴屏比我们强、是我们没做的第二步"这一说法不成立——主表面已实现。仍未贴屏的只是次要表面（直播卡片、私信图片、收藏列表、头像、UP 主空间），价值较低，未在本轮处理。

**Build 155**：修复 CDN 语法（`?imageView2/...` 被 hdslb 忽略→改 `@w_h[_q]q.webp` 后缀），并首次引入压缩清晰度选项。

**Build 156（本轮，用户要求"更易懂"）**：把两个旋钮合并为一个「图片清晰度」档位 `RemoteImageClarityPreset`（自动/省流/高清/原图），每档同时驱动尺寸上限（`sizePreference`）与压缩 q（`quality`）：
- 自动 → sizePreference .automatic（网络/电量/发热自适应）+ q nil（CDN 默认 75）
- 省流 → .dataSaver（560px）+ q 60
- 高清 → .high（2600px）+ q 90
- 原图 → .high（2600px）+ q 100

`RemoteImageQualityPreference.effectiveMaximumPixelLength` 静态入口改读统一档位的 sizePreference；`biliResizeSuffixURL` 改读统一档位的 quality；移除独立的 `RemoteCoverClarityPreference`；LibraryStore 与设置页各只剩一个属性/选择器。`stored()` 含一次性迁移：统一键缺失时回退旧尺寸键（high→高清、dataSaver→省流、automatic/balanced→自动）。尺寸贴屏机制（AdaptiveVideoCoverImage）不变，统一档位只影响其上限与压缩。
