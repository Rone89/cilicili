# Build 47 真机恢复基线分析

## 报告身份与结论

本次收到的是 1.1.1 / **Build 47、schema 1**，不是 Build 48；所有包含 `sampleBuild` 的事件也均为 47。因此本报告只能作为旧版基线，不能用于确认 Build 48 修复成功或计算其性能改善。

- runID：`27A61EBA-0B5F-43B0-8B05-B90A2A63F088`。
- 时间：2026-11-02 19:02:36–19:12:47（Asia/Shanghai），约 10 分 11 秒。
- 上下文：`iPhone19,7`、iOS 27.2、Wi-Fi、AV1、1920×1080 / 25 fps、SDR、1 倍速、AVPlayer / dashLocalHLS，1080P 高清 / 华为云 CDN。
- 视频：`BV1REx46NEc4`，时长 3041 秒；报告未提供可用于确认安装包源码提交的信息。
- 计划 21 次，实有 21 个唯一试验 ID，七种情景各三次；运行状态 completed，20 次 observed、1 次 timeout。**completed 是测试计划跑完，observed 是取得指定证据，都不是性能或音画体验通过。**
- 原始报告本地保留于 `build/device-reports/build47-27A61EBA.json`（Git 忽略），原始附件 SHA-256：`12ab331bc2f2f5490366759992f77e0a6c7f9d147e46d2ed7b47cfac81c7043d`。

## 暂停后恢复

以下使用 `playToFrame`，表示发出播放请求至采样到推进的视频输出帧；不是屏幕呈现或可听声音时间。每组仅三次，不报告 P95。

| 情景 | 三次 playToFrame（ms） | 中位数（ms） | 结果 |
| --- | --- | --- | --- |
| 暂停 5 秒 | 140 / 163 / 161 | 161 | 3 observed |
| 暂停 30 秒 | 164 / 135 / 137 | 137 | 3 observed |
| 暂停 120 秒 | 138 / 143 / 161 | 143 | 3 observed |

9 次的 playToTransport 为 26–30ms，playToFrame 为 135–164ms；此小样本未显示随暂停时长增加而变慢。目标均标为 covered，loadedAheadSeconds 为 1.920–6.566 秒。不能由这些数据推出冷启动、冷缓存或断网表现。

actualPauseMilliseconds 比请求暂停时间多 724–745ms，中位数约 732ms。schema 1 没有 pauseCommandMilliseconds / pauseHoldMilliseconds 分解，因此不能把这段额外时间直接认定为音频会话停用耗时，或把它当作恢复耗时。需要 Build 48 的 schema 2 报告区分同步命令、暂停保持和调度开销。

## 播放中跳转

| 情景 | 引擎耗时中位数 | seek 完成 total 中位数 | 恢复 total 三次／中位数 |
| --- | --- | --- | --- |
| nearbySeek | 247ms | 461ms | 1100 / 1047 / 1003ms；1047ms |
| distantSeek | 264ms | 477ms | 1083 / 1431 / 919ms；1083ms |

六次均 observed，均取得同一 sampleID 的 seekReveal / recovered=true，目标均为 uncovered，loadedAheadSeconds=0。nearby 是测试情景名，不能因此视为命中缓存；也不能把 uncovered 等同于磁盘缓存未命中或 CDN 不可用。

六次恢复 total 减去 seek 完成 total 为 557–857ms。可见耗时不只在引擎 seek，但这段差值不是某一模块的独立计时，不能全部归因于稳定揭示窗口、缓冲或解码；本报告也没有首次加载计时。暂不据此缩短现有音画和帧资格保护。

## 暂停拖动的重复记录

三次 pausedSeek 的 keptPaused、progressAdvancedAfterPlayCommand 均为 true，outcome 均为 observed。但每次同一 sampleID 都出现第二条 seek：

| 次数 | 第一条 seek total | 第二条 seek total | 两条记录的接收间隔 |
| --- | --- | --- | --- |
| 1 | 302ms | 3258ms | 2956ms |
| 2 | 115ms | 3106ms | 2991ms |
| 3 | 152ms | 3080ms | 2929ms |

这些约三秒后的重复记录与 Build 48 文档描述的旧 watchdog 提早重试问题一致，但 schema 1 缺少 action 标签及显式播放请求时点，不能仅凭它把每条重复记录最终定性为某种 retry/rebuild，也不能将第二条 total 当作暂停后首帧延迟。此情景的 observed 不等于不存在多余重试。

## 连续拖动超时

三次目标均为 40% → 75% → 30%。

- 第一次 timeout：第一条 40% 记录为 seekPlaying，最终 30%（912.300 秒）的记录却变为 **seekPaused**；同一最终 sampleID 后续是 watchdog / recovered=false / total=2921ms。中间目标没有完成记录，不应推断为完全没有发出。最终目标没有有效恢复证据，不能把其 17ms 引擎耗时或 18ms seek total 当作成功恢复速度。
- 第二、三次最终目标均为 seekPlaying / seekReveal / recovered=true，最终目标恢复 total 分别 1327ms、652ms。这里是最终操作的计时，不是从第一次拖动开始的整个连拖耗时。
- 第一次的 playing → paused 转换直接支持 Build 47 在连续提交期间丢失播放意图的现象，与 Build 48 的修复范围一致；仍需 Build 48 真机复测确认修复效果。

## 下一步

1. 核对当前 App 版本 1.1.1（48），不要只依据安装文件名；即使设备当前已是 48，也可能复制到的是保留的 Build 47 历史报告。
2. 在相同视频、画质、编码、网络和速率下重新运行自动恢复测试并复制最终 JSON；核对 context.build、sampleBuild 为 48，schemaVersion 为 2。
3. 先检查最终连续目标是否保持 playing、是否取得关联恢复记录，再检查暂停拖动是否存在旧 deadline 的提前重试；若有重试，区分新播放请求后的完整恢复预算与旧计时器。
4. 再比较按情景的命令耗时、暂停 hold、playToFrame、seek/recovery total 和带 manual-pause ID 的音频会话停用事件。缺失字段、timeout 和中断单列，不记为零。

本轮只解析、校验及记录报告，没有修改播放器策略、重新构建、提交或推送。分析工作树分支为 `codex/seek-intent-and-paused-watchdog-build48`，HEAD 为 `8f7070c9622c6729c7f39a97d8e9be12ab103b60`；该 SHA 属于当前分析源码，不能反推为报告中 Build 47 安装包的提交。
