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

## 提交

- `4ec821a` AI 字幕实验（上一目标遗留，未验收）
- `b31fa60` app 端播放地址兜底路由
- `7048476` HDR10 VIDEO-RANGE + colr 注入（build 70）
- `6ed18aa` HDR 输出策略改为 .high/.never（build 71）
