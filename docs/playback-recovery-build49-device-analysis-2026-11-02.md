# Build 49 真机恢复分析

## 结论

本轮支持 **显式暂停的同步命令开销明显下降**：pause5/pause30/pause120 共 9 次的 pauseCommandMilliseconds 中位数由 Build 48 的 635.8ms 降为 5.1ms，本轮范围 4.3–7.6ms。后台音频会话停用成功完成，未计入同步暂停命令。不能把这一差异表述为视频加载或恢复整体加速约 99%。

21 次均 observed，0 timeout。连续拖动三次都在最后目标取得 seekPlaying / seekReveal / recovered=true；暂停拖动三次保持暂停并在显式播放后推进，未记录旧版约三秒后的重复 seek。播放后推进帧耗时仍与 Build 48 同一量级，没有一致、明确的恢复速度提升证据。

## 报告身份与校验

- 1.1.1 / Build 49、schema 2；所有有 sampleBuild 的记录均为 49。
- runID：`C2750928-9B1B-4799-8DFB-724EB93472B7`。
- 时间：2026-11-02 19:55:26–20:05:11（Asia/Shanghai），约 9 分 45 秒。
- iPhone19,7 / iOS 27.2，Wi-Fi、HEVC、1920×1080 / 25fps、SDR、1 倍速、AVPlayer / dashLocalHLS，1080P 高清 / 华为云 tf_hw。视频 `BV1REx46NEc4`，3041 秒，低电量模式关闭、thermalState=0。
- 已校验 21 个唯一试验 ID、七种情景各三次、12 个音频会话停用成功事件与原暂停 ID 关联、9 组暂停跨度及恢复帧关联、三次最终连续目标的 seek/recovery ID 和播放模式。
- 原报告保存于 `build/device-reports/build49-C2750928.json`（Git 忽略）。附件 SHA-256：`1aa41d83d12df405ce5b79be370f9309a6baad18fb8701470710928a969a7423`。

## 暂停命令与后台停用

下表均取普通暂停的相同 9 次口径，不混入 pausedSeek：

| 指标 | Build 48 中位数 | Build 49 中位数 | Build 49 范围 |
| --- | --- | --- | --- |
| 同步暂停命令 | 635.8ms | 5.1ms | 4.3–7.6ms |
| 音频会话停用调用 | 630.7ms（同步） | 106.0ms（后台） | 74.8–185.8ms |
| 同步播放命令 | 31.2ms | 31.5ms | 28.7–33.3ms |
| playToFrame | 157ms | 150ms | 96–152ms |

9 次 actualPauseMilliseconds 均等于 pauseCommandMilliseconds + pauseHoldMilliseconds；实际暂停比请求 hold 多约 7–19ms，不再多约 0.64 秒。后台停用在普通暂停的 91–202ms 接收时间内记录完成，均早于至少五秒后的播放请求；接收时间只用于核对事件先后，不当作系统调用耗时。

另三次 pausedSeek 的显式暂停命令为 5.5 / 4.3 / 4.9ms，各也有同 ID succeeded=true 的后台停用事件。12 次总计均成功，报告内没有停用失败记录。

这与 Build 49 将阻塞调用移出主线程的目标一致。但后台调用本身由约 631ms 变为约 106ms 只是这两轮的观察；调度、系统音频状态等未受控，不能承诺之后固定如此，也不能把后台调用与暂停命令相加还原为“主线程阻塞”。命令计时不是屏幕呈现或实际声音停止时间。

## 各情景对照

| 指标（各情景三次中位数） | Build 48 | Build 49 | Build 49 三次 |
| --- | --- | --- | --- |
| 暂停 5 秒 playToFrame | 106ms | 150ms | 150 / 152 / 150ms |
| 暂停 30 秒 playToFrame | 158ms | 151ms | 151 / 96 / 152ms |
| 暂停 120 秒 playToFrame | 157ms | 145ms | 97 / 151 / 145ms |
| nearbySeek 恢复 total | 982ms | 932ms | 1270 / 932 / 673ms |
| distantSeek 恢复 total | 915ms | 909ms | 959 / 909 / 737ms |
| 连续 seek 最后目标恢复 total | 728ms | 559ms | 536 / 559 / 731ms |

普通暂停恢复均有 covered 目标和有效推进帧关联；playToTransport 为 27–31ms。暂停恢复分组有快有慢，50ms 左右的采样间隔、每组仅三次，都限制了细微差异解释，不计算 P95 或整体加速百分比。

nearby/distant 的 6 次全部 uncovered、loadedAheadSeconds=0，均 seekReveal / recovered=true，没有记录 retry/rebuild 或 watchdog 失败。seek 引擎耗时中位数为 341 / 294ms，seek 完成 total 中位数为 350 / 314ms；恢复 total 减 seek 完成 total 为 510–645ms。这不是某个保护窗口或解码阶段的独立计时，不据此缩短音画和帧保护。

连续 seek 三次都以 30%（912.300 秒）为最终请求，seek/recovery sampleID 一致，playing 意图保留。第一轮没有前两个目标的完成记录，属于被取代的目标，不要求完成；最终目标 total 不能当作第一次拖动至结束的全程耗时。

pausedSeek 各只有一条 seekPaused / slider-engine 记录，total 为 500 / 201 / 200ms；keptPaused 和 progressAdvancedAfterPlayCommand 均为 true，没有同 ID 重复 seek。其报告没有完整的播放后帧恢复时间，不能将此 total 误作暂停后首帧耗时。

## 结论范围与下一步

- **本轮已验证的数据改善**：同步暂停命令从约 636ms 降到约 5ms，后台停用均成功；自动计划没有超时，未复现已修复的连续意图丢失和暂停 seek 重复记录。
- **仍待验证**：快速连点暂停／播放、停用在途期间切后台或导航、耳机／蓝牙／中断、真实触摸、可见黑帧和声音输出。自动计划普通暂停至少五秒、pausedSeek hold 约两秒，本轮停用早已完成，不能把它当作在途竞争的真机验证；相关竞争已有本地自动测试。
- 两轮编码、设备和视频相同，但 Build 48 为 CDN 自动选择，Build 49 为华为云 tf_hw；实际 CDN／缓存和系统状态未完全匹配。可以确认本轮暂停命令跨度下降，但不能据此量化 seek/CDN 或整体恢复速度的版本收益；首次视频加载也不在报告覆盖范围。
- 暂时保留 Build 49 和现有帧保护，无需据此继续改恢复窗口。后续优先补充快速操作的真机证据，再处理剩余测试环境依赖／键盘 UI 问题及提交整理。

本轮仅分析和记录，没有改代码、重跑构建、安装或推送。工作分支 `codex/seek-intent-and-paused-watchdog-build48`，HEAD `8f7070c9622c6729c7f39a97d8e9be12ab103b60`；Build 49 源码改动仍未提交，来源文件校验见本地 build-info.json。
