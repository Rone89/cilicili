# Build 50 真机快速操作分析

## 已核实

- 1.1.1（50）／schema 3，runID `2F07E584-DE45-4720-899F-C7F9A92DD681`；计划及实际均 30 次、ID 唯一，10 个情景各三次，所有 sampleBuild 为 50。
- 2026-11-02 21:27:49–21:38:18（Asia/Shanghai），10 分 29 秒。最终 status=failed：29 observed、1 failed，无 timeout、无 missingEvidence。
- 设备 iPhone19,7／iOS 27.2，Wi-Fi、HEVC、1080P／25fps／SDR／1 倍速、华为云 tf_hw，视频 `BV1REx46NEc4`，3041 秒，低电量关闭、thermalState=0。
- 原件 SHA-256：`be3ceccf57b925ad482a95f6ae8dc52a4934333fcdcf59a9b3aa0058876513fb`。原样副本 `build/device-reports/build50-2F07E584.json`（Git 忽略）。

## 新情景确实覆盖了在途竞争

| 情景 | 三次结果 | 最终播放 playToFrame |
| --- | --- | --- |
| 立即暂停／播放 | 3 observed | 188 / 240 / 240ms |
| 连续切换后播放 | 3 observed | 112 / 162 / 158ms |
| 连续切换后暂停 | 2 observed、1 failed | 不适用 |

9 个新试验中的 15 条 play 命令全部记录 audioDeactivationPending=true；六次最终播放的帧 ID 均匹配最后 playRequested。pending 包含排队工作，不能证明每条命令都与系统调用并行。23 条后台停用事件 succeeded 均为 true；连续暂停会合并在途停用，不能要求每条暂停都各有系统停用事件。

最后一次失败 trial `D7E60E82-6F5D-4834-B216-5278329F337B`：pause/play/pause/play/pause 分别约 0.1 / 26.0 / 49.7 / 75.0 / 109.9ms 发出；最终暂停前 pending=false，暂停命令约 1.05ms，随后新停用约 12.3ms 成功。keptPaused=false，原因为“暂停期间出现播放意图或播放状态”。前两次最终暂停的检查通过。不能把整轮写成 30 次通过。

报告没有把失败瞬间 wantsPlayback 与实际 isPlaying 分开保存，且最后暂停后没有推进帧记录。它证明暂停检查失败，不能单凭此认定真实出声、持续播放或旧音频停用失败。Build 51 补充三个独立失败检查字段，继续保留原失败条件。

## 既有情景与耗时

原七种情景 21/21 observed：最终连续 seek 均为 seekPlaying、同 ID seekReveal／recovered=true；最终恢复 total 为 528 / 618 / 719ms。pausedSeek 三次 keptPaused、显式 play 后进度推进检查均通过。nearbySeek 恢复 total 为 963 / 899 / 744ms；distantSeek 为 872 / 1027 / 715ms，均 uncovered、loadedAheadSeconds=0。它们从最后操作计时，不是整段连拖耗时。

| 普通暂停共 9 次 | Build 49 | Build 50 |
| --- | --- | --- |
| 暂停命令中位数 | 5.11ms | 5.66ms（4.15–7.47ms） |
| playToFrame 中位数 | 150ms | 163ms（107–166ms） |

两轮设备、视频、编码和 CDN 选择一致，但缓存、网络和系统状态未受控，三次分组及约 50ms 采样也限制细微差异解释。不据此宣称恢复整体改善或明确退化。同步暂停仍约 5ms，新的重点是最后暂停意图的可靠性。

## 本地复现与修复范围

新增真实本地 DASH／AVPlayer 回归，在同一 MainActor 周期内 play 后立即 pause，再释放执行权。Build 50 代码稳定触发两个断言：实际 player.rate 已为 0，但旧 KVO 回调仍恢复播放意图并发布 playing。

仅重新读取当前 timeControlStatus 仍复现；进一步在 playing 分支核验当前 rate>0 后，独立回归通过。两种观察均在回到 MainActor 后读取当前值，避免消费入队前的 rate/status 快照；保留原生播放控件的真实正速率意图同步，不加固定等待或放宽暂停测试。

这是已确定、可复现且与报告时序吻合的代码缺陷；原报告状态信息不足以证明它是该真机事件唯一原因。Build 51 仍需真机复验快速操作，实际音画、后台／导航／耳机和系统中断另行验收。
