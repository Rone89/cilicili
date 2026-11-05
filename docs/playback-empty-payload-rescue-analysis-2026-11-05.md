# "HDR 视频无法播放"诊断与修复（2026-11-05）

用户报告：HDR 视频无法正常播放，杜比视界可以。本次基于设备端诊断日志做实证分析，未在真机复现 HDR 场景本身。

## 诊断过程（数据来源：真机 App 容器 `Documents/player-diagnostics.log`，覆盖 2026-11-02 至 11-05）

1. **HDR 真彩（qn=125）在全部日志中出现次数为 0**：无任何 target=125 的播放请求，无任何变体列表包含 125d。杜比视界（126）仅在影视飓风样片（BV1NGZtBwELa）出现且可播放。
2. **找到 5 个用户真实打开但从未出帧的视频**：BV1Hhsd6dEs5、BV1MN4dewEQZ、BV1XY546vE1o、BV1ns4y1A7fj、BV1wHpt6GEXk（含 4K 视频与普通 720P 视频）。
3. **统一失败签名**：WBI 播放地址接口返回 **code=0 但载荷完全为空**（dashV0:dashA0:durl0:accept0:support0，`loggedIn1:sess1:dede1:access1` 凭据齐全）；qn=112 与 qn=80 兜底均空；webpage 路由部分视频可恢复、部分（BV1ns4y1A7fj）连 webpage 也 `missingPayload`。
4. 失败成批出现且与清晰度无关（720P 视频同样失败）——判定为 **B 站对 Web 播放地址请求的间歇性风控空载荷**，与 HDR 无关。用户恰好在测 HDR 内容时连续踩中，误归因为 HDR；杜比样片恰好正常完成启动，形成"HDR 不行、杜比行"的印象。

## 选择链路审计（未发现 125 特有缺陷）

- fnval=4048（含 HDR 64 位 / 杜比 2048 位）全部请求一致。
- `PlaybackCodecPolicy.canDecode(.hdr10/.dolbyVision)` 均归一为 HEVC 硬解探测，真机对称。
- `isHardwareDecodingCompatibleVideo` 对 HDR10 的 `hev1` 字符串经 `isHEVCVideoCodec` 分支覆盖。
- 质量菜单构建、变体构建、`DashStreamDispatcher` 选流排序对 125/126 无差异处理。
- 用户的编码偏好为 AV1 优先、首选清晰度 1080P60（来自设备 UserDefaults），HDR/杜比需要手动在清晰度菜单选择。

## 修复：app 端播放地址兜底路由

`BiliAPIClient+PlaybackAppEndpoint.swift`（新增）+ `BiliAPIClient+PlaybackStartupRace.swift`（接入）：

- 触发条件：UGC 启动竞速的**全部**路由（WBI + Webpage）均未产出可接受的播放地址（即本次 5 个视频的全失败场景）。
- 动作：请求 `https://app.bilibili.com/x/v2/playurl`，参数 access_key + appkey/ts/sign（复用 `BiliAppSigner`，与投币修复同一套 app 端签名设施），profile `.androidLogin`。
- 鉴权独立于 Web 风控体系（扫码登录的 access_key，设备诊断确认 `access1` 存在）。
- 校验：响应需含可用视频流（dash 视频流 + 最佳音频，或 durl）；失败则维持原失败行为，不引入回归。
- 日志：`startupAppEndpointRescue result=...`（含耗时与可达清晰度），无 access_key 时记录 `skipped reason=noAccessKey`。
- 限制：仅覆盖 UGC 启动竞速；PGC（番剧）播放链路未接入。app 端接口若返回 durl（MP4）则为降级播放，可恢复"能播"。

## 睡醒后的真机验收

1. 重进之前打不开的视频（如 BV1ns4y1A7fj 罗肖尼、BV1XY546vE1o 刘谦），应能出帧播放；诊断日志出现 `startupAppEndpointRescue result=success`。
2. 若依然失败：日志会显示 rescue 的失败原因（如 app 端接口返回码），据此继续定位。
3. HDR 真彩（125）单项验证：找一个官方 App 里明确显示"HDR 真彩"的视频，App 内清晰度菜单应出现 HDR 真彩选项；若菜单仍无该选项，先在官方 App 确认该视频当前确实提供 125，再把视频 BV 号记录下来继续排查（本轮日志无法确认用户的 HDR 测试视频是哪一条）。

## 追加：HDR 分辨率可播但无 HDR 效果（同日第二轮）

用户补充：HDR 分辨率可选、能播，但画面没有 HDR 效果。重新拉取设备诊断日志后确认现场：

- `2026-11-05T04:51:30Z` 番剧《107 上苍》（BV1QMxz6hEV5）播放地址返回 `qualities=125d,120d,...`，用户手动切到 **HDR 真彩（q125）**。
- 切换后 HLS 走 `codec=hvc1.2.4.L153.90`、`res=3840x2160`、`bridge=true`，播放正常。
- 对比：两条杜比视界视频（BV1vU4P6gEf3、BV1HEf2YWEvs）在 Manifest 事件里均有 `nativeHDR=localVideoHLS ... codec=dvh1.../hvc1...` 记录，HDR 真彩这条没有任何 range 相关记录。

根因（代码层，已定位）：

1. `HLSRendition.hlsVideoRangeValue` 对非杜比轨只信任 init 段的 `colr` box（`videoColorInformation`）。B 站 HDR10 流的 init 段若缺少 `colr`、或 transfer 不是 PQ(16)/HLG(18)，`VIDEO-RANGE` 属性整个缺失，AVPlayer 按 SDR 渲染 —— 表现正是"能播、但没 HDR 效果"。
2. `BiliVideoDynamicRange.hlsVideoRangeAttribute` 对 `.hdr10` 曾返回 `nil`（刻意"不猜测"，有单测守护），因此没有任何按动态范围的兜底。
3. `normalizedHEVCInitializationDataForHLS` 只把 `hev1` 重写为 `hvc1`，不像杜比路径那样补齐 `colr`（杜比路径有 `addingHLGColorInformationIfMissing`），HDR10 的 init 段因此可能完全没有颜色信息。

修复（保守、可验证）：

- `HLSRendition.hlsVideoRangeValue`：colr 优先；缺失时按 **B 站权威画质码**兜底 —— 仅 q125（HDR 真彩）/ q129（HDR Vivid）标 `PQ`，`.hlg` 标 `HLG`，其余 HDR10（标题推断）仍不猜测。
- `DolbyVisionCodecConfiguration.normalizedHEVCInitializationDataForHLS(_:dynamicRange:)`：对 `.hdr10` 注入 BT.2020 + PQ（primaries 9 / transfer 16 / matrix 9）`colr`，对 `.hlg` 注入 transfer 18；仅当源 init 段没有 colr 时注入。HLG 注入实现泛化为通用 transfer 参数，原杜比路径行为不变。
- 诊断增强：Manifest 持久化记录新增 `version=` 与 `hdr=q<画质> range=<PQ/HLG/-水平> color=<primaries/transfer/matrix>`；video-only 路径记录也补 `range/color`。下次真机测试可直接从 `Documents/player-diagnostics.log` 核准 `VIDEO-RANGE` 是否生效。

单元测试：`DolbyVisionCodecConfigurationTests` 新增 HDR10 PQ 注入、SDR 不注入、画质兜底白名单（125/129 才 PQ）三组断言；保留原有"HDR10 不按标题猜测"断言。

验收（睡醒后）：

1. 重进《107 上苍》等有 HDR 真彩的视频 → 播放器设置里切换 HDR 真彩。
2. 画面应进入 HDR 显示（高光更亮、暗部层次更明显；可在系统控制中心/照片 HDR 对比）。
3. 诊断日志应出现 `hdr=q125 range=PQ`（若 init 自带 colr 则 range 仍为 PQ）；`version=8` 表示 master playlist 已带 `VIDEO-RANGE`。
4. 若日志显示 `range=PQ` 但画面仍无 HDR 效果，则问题在渲染输出层（AVPlayerLayer/EDR），需继续从该层排查。

## 追加二：build 70 真机验证仍无 HDR 效果（第三轮）

用户在 build 70 上仍反馈"HDR 分辨率可选，但没有 HDR 效果"。拉取设备日志确认 **manifest 层修复已生效**：

```
2026-11-05T05:16:00Z event=Manifest metricsID=BV1QMxz6hEV5
message=server=2ms routes=508 variants=1 codec=hvc1.2.4.L153.90 version=8
hdr=q125 range=PQ color=nclx primaries=9 transfer=16 matrix=9 limited codec=hvc1.2.4.L153.90
```

即 master playlist 已带 `VIDEO-RANGE=PQ`（version=8），init 段已含 BT.2020/PQ colr。问题由此确认在**渲染输出层**：

- 主 HLS 播放层 `applyDisplayDynamicRangePolicy(to: AVPlayerLayer)` 对 HDR 源设置的是
  `preferredDynamicRange = .automatic` + `toneMapMode = .automatic`。
- 杜比视界能正确出 HDR，是因为它走 `NativeDolbyVideoOverlayRenderer` 的直连静音层，
  该层显式设置 `preferredDynamicRange = .high` + `toneMapMode = .never`（真 HDR 输出）。
- 按 QuartzCore SDK 文档：`preferredDynamicRange` 默认 `.standard`；`.automatic` 不保证激活
  EDR，`.high` 才会按显示能力输出高动态范围；`toneMapMode = .automatic` 允许系统把画面
  tone-map 回 SDR。二者叠加导致 HDR10 画面被按 SDR 输出——与用户观感一致。

修复（build 71）：

- `applyDisplayDynamicRangePolicy(to layer:)` 与 `(to controller:)`：HDR 源改为
  `preferredDynamicRange = .high`、`toneMapMode = .never`；SDR 源保持 `.standard` + `.automatic`。
  与杜比直连层策略保持一致。
- 诊断：`displayPolicy target=layer hdr=true preferred=high toneMap=never` 会持久化到
  `player-diagnostics.log`，用于确认策略实际应用。

验收（build 71）：

1. 重进《107 上苍》等视频，切 HDR 真彩，观察高光/暗部层次是否出现 HDR 观感。
2. 日志应出现 `hdr=q125 range=PQ ... version=8` 与 `displayPolicy target=layer hdr=true preferred=high toneMap=never`。
3. 若两者都在但画面仍为 SDR，则继续排查：视频采样位深（是否 10-bit）、
   AVPlayerItem 输出、或系统 HDR 显示设置；届时需抓取更底层的解码/渲染诊断。

### 真机验证结果（2026-11-05 05:26–05:29，build 71，**用户确认 HDR 观感正常**）

低层数据与观感一致：

| 项目 | BV1QMxz6hEV5《牧神记 107 上苍》(PGC) | BV1R1e4zKEh1《4KHDR 真彩样片》 |
| --- | --- | --- |
| 画质 | q125（targetQ=116 为偏好值，手动切 HDR） | q125 |
| manifest | `version=8`、`range=PQ` | `version=8`、`range=PQ` |
| init colr | `nclx primaries=9 transfer=16 matrix=9 limited`（BT.2020/PQ） | 同上 |
| CODECS | `hvc1.2.4.L153.90`（HEVC Main10 / Level 5.3） | `hvc1.2.4.L153.90` |
| 输出策略 | `displayPolicy hdr=true preferred=high toneMap=never` | 同上 |
| 首帧 | 5.12s | 1.40s |
| 码率/稳定性 | indicated 10.06 Mbps，stalls=0，buffer 1.35s | indicated 21.84 Mbps，stalls=0 |

结论：画质选择 → HLS 签名（VIDEO-RANGE=PQ）→ init 颜色信息 → 输出层 EDR 策略 → 稳定播放，全链路数据一致，HDR 生效已确认。

观察到的两个非阻塞问题（与 HDR 无关，后续可单独处理）：

1. `startupAppEndpointRescue result=failure ... DecodingError.dataCorrupted`：app 端播放地址兜底对该 PGC 集返回非 JSON 载荷。兜底失败会被正常吞掉，不影响其它路由，但说明 app 端接口对 PGC 需要不同参数/端点，后续需修正或限定只对 UGC 使用。
2. `manualAvailability failed q125 error=API -404: 啥都木有`：清晰度可用性探测对该集返回 -404，但实际播放 q125 正常；探测结果可能让菜单短暂显示"待确认"，不影响播放。

### 两个非阻塞问题的修复（build 72）

**问题 1：app 端兜底路由端点错误**

- 原因：使用了不存在的 `https://app.bilibili.com/x/v2/playurl`，服务端返回非 JSON 载荷，触发 `DecodingError.dataCorrupted`。
- 修复：改用真正的 app 鉴权端点 `https://api.bilibili.com/x/player/playurl`，参数为
  `access_key + bvid + cid + qn + fnval=4048 + fnver=0 + fourk=1 + mobi_app=android +
  platform=android + build=<profile>`，并附带 appkey/ts/sign（`BiliAppSigner.sign`）与登录 Cookie。

**问题 2：PGC 播放信息 -404 导致清晰度解析失败**

- 原因：部分剧集（实测《牧神记》107 集）的 PGC 播放信息或 web playurl 返回 `-404 啥都木有`，
  但同一 bvid/cid 的启动期 target-first WBI / webpage 路径可用。
- 修复：新增 `fetchPlayURLForManualQuality` 逐级回落：
  PGC playinfo → UGC `fetchPlayURL` → `fetchPiliPlusStyleStartupPlayURL` → `fetchWebPagePlayURL`。
  同时给启动播放、播放恢复、听视频预加载的 PGC 分支补上 PGC→UGC 回落（仅在错误时触发，
  不改变成功路径）。

验收（build 72）：

1. 《牧神记》107 集切 HDR 真彩：日志应出现 `manualAvailability resolved q125`，不应再出现 `-404`。
2. 若启动期所有 web 路由均失败，app 端兜底应记录 `startupAppEndpointRescue result=success`（不再出现 `dataCorrupted`）。
3. HDR 表现应维持 build 71 已验证的状态（`range=PQ` + `displayPolicy hdr=true preferred=high toneMap=never`）。

## 提交

- `4ec821a` AI 字幕实验（上一目标遗留，未验收）
- `b31fa60` app 端播放地址兜底路由
- `7048476` HDR10 VIDEO-RANGE + colr 注入（build 70）
- `6ed18aa` HDR 输出策略改为 .high/.never（build 71）
- `9cac0a3` app 端端点修正 + PGC→UGC 回落（build 72）

## 追加三：视频详情页掉帧的真正原因——评论自动分页失控（build 90/91）

经过启动参数驱动的自动自测（`--hitch-self-test` + `--hitch-mode`）反复 A/B，最终定位：

- 现象：特定视频播放页前 40–50 秒 fps 2–8、p95 300–500ms，之后恢复 45–85fps；与 HDR/EDR、清晰度、弹幕开关、渲染器、滚动、seek 位置、网络下载量均无关。
- 决定性实验：`skipCommentLoading` 跳过评论加载后，同一视频从第 1 秒起 59–100fps、p95 16.7ms、内存完全平稳。
- 量化证据：45 秒内 `commentPageLoaded` 连续记录 **64 页 / 1196 条评论**（约 1.4 页/秒），可用内存下降约 750MB 后稳定。
- 根因：评论列表 footer 用零高度视图的 `onAppear` 自动加载下一页，且以"最后一条评论 id"作为视图 id；每加载一页 id 变化 → 视图重建 → 再次 `onAppear`，形成无节流的分页循环，直到评论全部加载完。

修复：

- `CommentsSectionLoadMoreFooter` 移除自动触发，改为显式的「加载更多评论」按钮（带 loading/失败重试状态）。
- 回退 build 75 基于误判的"HDR 播放强制 DanmakuKit"逻辑；弹幕渲染器重新遵循用户的 Metal 实验开关（验证表明两种渲染器在 HDR 下均流畅）。

验证（build 90/91，自动自测）：

- 同视频 1080P：24 个窗口最低 58.6fps，p95 全部 16.7ms，内存平稳，评论只加载 1 页。
- HDR 无弹幕：59–60fps / p95 17ms；HDR + Metal 弹幕：60–89fps / p95 17ms。

UX 变化：评论不再自动无限加载，需要点击「加载更多评论」按钮继续加载。

### 最终方案：滚动几何触发（build 92→93）

build 92 曾改回 `onAppear` 自动加载，自测显示仍会失控（LazyVStack 预取范围内 footer 反复触发，65 页再次全部拉完）。最终改为：

- `CommentsSectionLoadMoreFooter` 用 `onScrollGeometryChange` 监听滚动位置，仅当距列表底部 < 700pt 时自动加载下一页；保留点按加载与"正在加载/失败重试/没有更多"状态。
- `loadMoreComments()` 增加 PiliPlus 式总数判尾：已加载条数 ≥ `detail.stat.reply` 时置 `commentsEnd`。

验证（build 93，自动自测 sdr 模式含滚动阶段）：同一视频 24 个窗口最低 59fps、滚动阶段最高 103fps，p95 全程 16.7ms，静置只加载 1 页，滚动开始才触发下一页。UX 与 PiliPlus 一致（滚动到底自动加载）。

诊断过程要点（供后续参考）：

- 排除法曾误指向 HDR/EDR、弹幕渲染器、网络流式下载等，最终靠 `skipCommentLoading` A/B 和 `commentPageLoaded` 计数锁定评论分页循环。
- `--hitch-self-test --hitch-mode <off|kit|metal|sdr|nostream|nocomment>`（配合 `--start-detail --start-bvid ...`）可全自动复现与回归，性能类问题建议优先搭建此类可编程复现通道。
