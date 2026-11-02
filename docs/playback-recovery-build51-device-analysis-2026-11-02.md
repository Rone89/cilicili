# Build 51 真机恢复分析

## 本轮结论

30/30 observed，0 failed、0 timeout、0 missingEvidence。连续切换后保持暂停三次均 keptPaused=true，Build 50 的最终暂停检查失败本轮未复现；六次最终播放的推进帧均匹配最后 playRequested ID。

这是本轮条件下的控制流证据，不是所有竞态、实际声音／画面或整体性能验收完成。尤其三次最终暂停时 pending 全为 true，尚未覆盖 Build 50 失败时“停用刚结束、最后暂停前 pending=false”的真机边界。

## 报告身份与校验

- 1.1.1（51）／schema 3，runID `65833B09-22BE-46EB-BACD-7D0A30D863FA`。
- 2026-11-02 22:30:22–22:40:53（Asia/Shanghai），10 分 31 秒；status=completed。
- 计划和实际均 30 次，ID 唯一、10 个情景各三次，repetition 为 1/2/3，所有 sampleBuild 为 51；所有导出的 checks 均为 true。
- iPhone19,7／iOS 27.2，Wi-Fi、HEVC、1920×1080／25fps／SDR、1 倍速、AVPlayer／dashLocalHLS，1080P／华为云 tf_hw；视频 `BV1REx46NEc4`，3041 秒，低电量关闭、thermalState=0。
- 附件 SHA-256：`0f86d02f71ddc9236505f162e50e81fe7a8e1e71910c6ac67af0f1535e893f05`；原样归档 `build/device-reports/build51-65833B09.json`，机器可读核验 `build/device-reports/build51-analysis.json`（均 Git 忽略）。
- 安装来源见上一轮 `build/logs/build51-device-build-info.json`：本地 Xcode 27.1 Release，源码后续备份为 `aa562916`。原始报告不含 Git SHA，不能只凭 build 字段反推任意安装包提交。

## 快速操作与覆盖边界

| 情景 | 三次结果 | 最终 playToFrame |
| --- | --- | --- |
| 暂停后立即播放 | 3 observed | 348 / 347 / 347ms |
| 连续切换后保持播放 | 3 observed | 314 / 266 / 264ms |
| 连续切换后保持暂停 | 3 observed，keptPaused=true | 不适用 |

9 个新试验中 15 条 play 命令全部 pending=true；21 条音频会话停用事件均 succeeded=true。对仍在途的暂停合并停用，本轮 21 条而 Build 50 为 23 条与最后暂停的时机不同一致，不是缺两条或系统调用次数优化的证明。pending 包含排队工作，不证明系统调用在每条命令发生时都并发执行。

三次最终暂停分别约 99.0 / 98.5 / 100.6ms 发出，pending 均为 true；对应停用完成事件约 174.6 / 195.0 / 175.6ms 才收到。即最后暂停先于激活等待结束，原有代数／所有权保护可以拒绝旧播放。

Build 50 的失败最终暂停约 109.9ms 发出，其前 pending=false；停用完成事件约 93.5ms 已收到。Build 51 本轮没有命中这个时序，不能仅以 30/30 observed 宣布这一路径真机验证完成。已完成的本地真实 AVPlayer 红绿回归仍有效，二者覆盖范围分开记录。

下一步优先补可控的真机自动情景：先等待停用完成，再于同一主线程周期 play→pause，记录命令前 pending、实际播放状态和最后意图，然后等停用结束并检查暂停保持。保留在途竞争场景；不再只靠固定 20ms 间隔或重复整套十分钟计划偶遇边界。此项本轮尚未实现，不新增播放器行为改动。

## 耗时对照

普通暂停为 pause5/30/120 共 9 次，seek 每组各三次，单位 ms：

| 指标（中位数） | Build 49 | Build 50 | Build 51 |
| --- | --- | --- | --- |
| 同步暂停命令 | 5.11 | 5.66 | 4.66（1.76–5.12） |
| 同步播放命令 | 31.51 | 32.74 | 32.14 |
| 普通暂停 playToFrame | 150 | 163 | 151（99–156） |
| 后台音频会话停用调用 | 106.0 | 88.1 | 181.0（122.2–190.6） |
| nearbySeek 恢复 total | 932 | 899 | 670 |
| distantSeek 恢复 total | 909 | 872 | 754 |
| 连续 seek 最后目标恢复 total | 559 | 618 | 657 |
| 立即恢复 playToFrame | 未覆盖 | 240 | 347 |
| 连续切换后播放 playToFrame | 未覆盖 | 158 | 266 |

本轮同步暂停仍约 5ms，普通恢复与 Build 49/50 为同一量级；立即恢复和快速切换后恢复本轮更慢，不能将 30 observed 表述为更快。

立即恢复从最终 playRequested 到停用完成事件接收约 193–195ms，Build 50 约 108–112ms；事件接收到 transportPlaying 又约 46–48ms，Build 50 约 24ms。连续切换后播放的前一段约 106–113ms，Build 50 约 15–25ms。这些是接收时间差，包含排队、激活／状态同步和日志接收延迟，不能独立当作 setActive、解码或渲染耗时。它们与本轮等待变长相符，但不足以确定版本退化原因。

三轮设备、视频、编码及 CDN 选择一致，缓存、网络和系统音频状态未受控；Build 50 为云端 Xcode 26 Release，Build 51 为本地 Xcode 27.1 Release。工具链也不同，不是严格性能对照。每组仅三次且帧采样约 50ms，不计算整体加速比例或 P95。

nearby/distant 共六次均 uncovered、loadedAheadSeconds=0、seekReveal／recovered=true；连续 seek 三次最终目标均为 912.300 秒、seekPlaying、同 ID 恢复；pausedSeek 三次各一条 seek，暂停保持及显式播放后进度检查均通过。total 从对应最后操作计时，不是整段连续拖动耗时，也不代表首次视频加载。

## 当前处理

保留 Build 51 和现有音画／帧保护，本轮不改代码、不新建 Build、不重复构建或测试。下一步补停用完成后的自动边界覆盖，随后补实际声音、后台／导航、耳机／中断及横竖屏验收，再决定性能优化。

另已核实旧版源码 `317f89b` 的 CI #153 attempt 2 最终成功，ui-4 重跑 35/35、无失败后重试；结合保留结果为 1220 单元、141 UI、12 交互及 Release 最终通过。首轮失败及先前重试记录仍保留，此为 Build 50 的云端结论，不是 Build 51 云端回归。
