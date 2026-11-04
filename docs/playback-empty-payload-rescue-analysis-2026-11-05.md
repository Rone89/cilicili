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

## 提交

- `4ec821a` AI 字幕实验（上一目标遗留，未验收）
- `b31fa60` app 端播放地址兜底路由（本轮修复）
