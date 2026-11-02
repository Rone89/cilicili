# Build 48 真机恢复分析

## 已核实结果

- 1.1.1 / Build 48、schema 2；所有包含 sampleBuild 的记录均为 48。runID：`CE0673F5-9896-454D-BB4F-E616E715A55A`。
- 2026-11-02 19:18:20–19:28:12（Asia/Shanghai），约 9 分 52 秒。运行 completed，21 个唯一试验 ID，七种情景各三次，21 observed、0 timeout。
- 逐条校验了最终连续目标的 seek/recovery sampleID、seekPlaying 模式、recovered=true；三次 pausedSeek 的两项状态检查均为 true；12 个音频会话停用事件均与各自 manual-pause ID 一致，succeeded=true。
- 原始报告本地保存于 `build/device-reports/build48-CE0673F5.json`（Git 忽略）。原始附件 SHA-256：`31059d71019d97cc077cff2a4d4bc950ecc3c2bbc11d94047eedf9d311c4416b`。
- 本轮没有修改播放器、构建或安装新包；只解析报告、核对证据及更新文档。工作分支 `codex/seek-intent-and-paused-watchdog-build48`，HEAD `8f7070c9622c6729c7f39a97d8e9be12ab103b60`，本地改动尚未提交。已安装包来源及重签信息见 DEVELOPMENT_STATUS.md。

observed 只表示取得该情景要求的证据，不能据此宣布真实触摸、黑帧、屏幕呈现、声音输出、冷启动、冷缓存或总体性能验收通过。

## 连续拖动：本轮未复现播放意图丢失

三次都提交 40% → 75% → 30%，最终请求 912.300 秒：

| 次数 | 最终目标模式 | 最终 seek total | 最终目标恢复 total | 结果 |
| --- | --- | --- | --- | --- |
| 1 | seekPlaying | 42ms | 556ms | seekReveal / recovered=true |
| 2 | seekPlaying | 81ms | 728ms | seekReveal / recovered=true |
| 3 | seekPlaying | 77ms | 730ms | seekReveal / recovered=true |

三次最终恢复中位数 728ms；所有记录 action 为 slider-engine-resume。第一轮只有最后目标的完成记录，之前的目标被取代，不要求它们各自完成，也不能按缺少前两个完成记录判失败。

Build 47 三次中有一次最终模式变为 seekPaused、watchdog recovered=false 并超时；Build 48 本轮三次均未复现该现象，支持修复在本轮条件下有效。不能由 3 次推断问题在所有视频／编码／网络或实际触摸路径下彻底消除。这里的 total 从最终操作计时，不能当作第一次拖动至完成的整段耗时。

## 暂停拖动：本轮未记录旧版重复 seek

三次均 keptPaused=true、progressAdvancedAfterPlayCommand=true；各只有一条 seekPaused / slider-engine 记录，total 为 742 / 135 / 142ms。没有 Build 47 三轮均出现的约三秒后同 ID 第二条 seek，也没有报告内的 retry/rebuild action 或 watchdog 失败记录。

这支持旧 watchdog 提前重试在本轮未复现。此情景没有完整的播放后首帧恢复计时；其 observed 基于暂停保持及显式 play 后进度推进，不能把 seek total 当成播放恢复延迟，或声称已验证所有 stale-video 恢复预算路径。

## 显式暂停耗时：音频会话停用占主导

以 pause5/pause30/pause120 共 9 次作为同一统计口径：

| 指标 | 中位数 | 范围 |
| --- | --- | --- |
| pauseCommandMilliseconds | 635.8ms | 633.3–650.0ms |
| 同 ID audioDeactivationMs | 630.7ms | 627.6–643.9ms |
| playCommandMilliseconds | 31.2ms | 28.1–32.5ms |
| playToFrame | 157ms | 105–161ms |

逐次音频会话停用占同步暂停命令的 98.99%–99.27%。因此，这轮可明确把约 0.63 秒的同步暂停开销定位到音频会话停用调用，而不必再像 schema 1 一样从实际暂停时间间接推测。它不是 play 后视频帧恢复耗时。

9 次均满足 actualPauseMilliseconds = pauseCommandMilliseconds + pauseHoldMilliseconds（误差 <0.01ms）；实际 hold 比请求 hold 多 0.7–10.4ms，说明额外等待主要来自同步暂停命令，不是 5/30/120 秒的 hold 多等了约 0.63 秒。暂停拖动另三次也各有约 0.63 秒的显式暂停命令；随后 seek 命令本身为 10.7–14.0ms。

下一步开发优先调查显式暂停的音频会话停用：确认主线程阻塞路径与音频所有权，再评估异步停用或延后停用能否保留显式暂停、后台、导航和音频中断语义。不能直接把所有显式 pause 改为静默 scrub pause，也不能由函数耗时直接断言用户实际看到 UI 卡顿。任何修复都需覆盖 pause/play 竞争，避免旧停用请求影响新播放。

## 与 Build 47 的耗时对照及限制

| 指标（每组 3 次的中位数） | Build 47 | Build 48 |
| --- | --- | --- |
| 暂停 5 秒 playToFrame | 161ms | 106ms |
| 暂停 30 秒 playToFrame | 137ms | 158ms |
| 暂停 120 秒 playToFrame | 143ms | 157ms |
| nearbySeek 引擎耗时 | 247ms | 318ms |
| nearbySeek 完成 total | 461ms | 328ms |
| nearbySeek 恢复 total | 1047ms | 982ms |
| distantSeek 引擎耗时 | 264ms | 406ms |
| distantSeek 完成 total | 477ms | 408ms |
| distantSeek 恢复 total | 1083ms | 915ms |

两轮同一 iPhone19,7、iOS 27.2、Wi-Fi、同视频、1080P / 25fps / SDR / 1 倍速，但条件并非完全相同：

- Build 47 是 **AV1 / CDN 华为云 hw**；Build 48 是 **HEVC / CDN 自动选择**，报告没有给出自动选择的实际服务端主机。
- Build 48 为重签后独立 bundle/container，登录、设置和缓存不自动继承。不能假定两轮缓存或实验设置完全一致。
- 两轮各情景仅三次；恢复帧按约 50ms 采样。暂停恢复结果并非各组一致更快。
- nearby/distant 六次目标仍全为 uncovered、loadedAheadSeconds=0；恢复 total 为 710–1021ms 和 704–1138ms，均为 seekReveal。恢复 total 减 seek 完成 total 为 503–654ms，但此差值不是某一保护窗口、缓冲或解码模块的独立计时。
- 没有首次视频加载计时；不能据此判断首次加载性能，不能计算或宣传 Build 48 的整体加速百分比。

可确认的是本轮控制流异常未复现，以及同步暂停耗时的直接分解；量化版本性能差异仍需匹配编码、CDN 和设置后再采样。

## 待办

1. 优先定位并处理音频会话停用的同步暂停开销，保持现有播放／暂停和音频生命周期约束，测试竞态后递增构建号交付。
2. 量化版本间性能时，再将两版本设为相同编码、CDN、画质和速率；现有两轮保留为条件不同的观察，不丢弃也不混算。
3. 下一包重点复验暂停指令耗时是否下降、暂停后无意外声音／播放，以及连拖最终目标和暂停拖动回归。真实可见黑帧、声音输出和冷启动仍需额外证据。
4. 本地已知的 1 项单元失败、2 项键盘 UI 失败及尚未提交的编译兼容修复继续单列处理，本报告不代表这些问题已解决。
