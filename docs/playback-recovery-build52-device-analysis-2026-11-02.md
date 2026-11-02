# Build 52 暂停边界真机报告分析（2026-11-02）

## 结论与范围

本轮 `pauseBoundary` 短测 3/3 observed，零失败、超时或缺证。三次均补齐 Build 51 报告缺少的“音频停用已结束后，同一 MainActor 周期 play→pause”边界，并保持最终暂停；Build 50 的暂停后播放意图／状态异常本轮未复现。三次样本不能证明所有时序均无竞态，也不代替实际音画与性能验收。

这轮仅校验、归档报告和更新文档，未修改播放器、创建新 Build、构建／安装或重跑自动测试。Build 52 播放器生产逻辑沿用 Build 51；本地历史验证为 1228 单元、3 项重点 UI 最终通过，云端 Build 50 CI #153 不覆盖本版本。

## 报告身份与校验

- Run ID：`F788D232-E597-4FA5-9CF2-048BFA6833CF`；schema 4，Build 52，`testPlan=pauseBoundary`，planned=actual=3，status=completed。
- 时间：2026-11-02 23:09:55–23:10:14（Asia/Shanghai），按报告秒精度跨度 19 秒。
- 环境：iPhone19,7／iOS 27.2，Wi-Fi，低电量模式关闭，thermalState=0；AVPlayer／dashLocalHLS，HEVC／SDR／1080P／25fps／1x，华为云 tf_hw，视频时长 3041 秒。
- 原始附件 SHA-256：`4335d3b72f184c3ce4f5a1a027d912d49193d27b587ae635b2dcbca5625ca11a`。
- 三个 trial ID、repetition 1/2/3、六个暂停 sampleID 唯一；每次原暂停与 playRequested／transportPlaying 同 ID，两次停用分别归属原暂停和最后暂停，六次均 succeeded=true。六条带版本的播放／transport 记录均为 sampleBuild=52。
- 原报告与逐项断言核验位于 Git 忽略的 `build/device-reports/build52-F788D232.json`、`build52-analysis.json`；复核脚本 `analyze-build52.py` 同目录。检查过命令时序、状态、覆盖条件、ID 归属和版本，未只依赖 outcome 字符串。

## 边界覆盖

三次 commands 均为 pause→play→pause，所有命令开始前 pending=false；命令后 isPlaying 和 wantsPlayback 均依次为 false→true→false。五个覆盖／保持检查均 true。第一次停用完成事件的收到时间逐次早于 play 命令，最后停用也都有独立成功记录。

play 返回至最后 pause 开始之间的记录间隔分别约 0.009、0.020、0.108ms，与代码中连续调用、无 await 一致；这些是同步记录开销，不是帧恢复时间。最终暂停等待停用结束后继续保持暂停的既有检查通过，即使第二次停用较慢也未出现意图恢复。报告未提供独立逐帧／音频输出验证，isPlaying 是既有引擎快照。

## 耗时与限制

单位为毫秒；“停用”列是后台系统调用跨度，“暂停／播放命令”列是同步 API 工作。

| 次数 | 原暂停命令 | 播放命令 | 最后暂停命令 | 原暂停停用 | 最后暂停停用 | playToTransport |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 4.334 | 12.768 | 0.469 | 107.7 | 9.8 | 12 |
| 2 | 5.545 | 34.633 | 1.068 | 171.7 | 786.7 | 32 |
| 3 | 6.936 | 37.173 | 1.067 | 171.4 | 15.8 | 36 |

第二次最后停用 786.7ms，最后暂停命令仅 1.068ms；其完成记录在 trial 1049.276ms 收到，命令在 254.266ms 开始。可以确认系统停用长尾与同步暂停跨度分离，不能据此宣称没有任何 UI 卡顿，或推断该系统调用变慢的具体原因。本轮无需因这一条记录改回同步停用或缩短恢复保护。

playToTransport 中位数 32ms，只说明进入 transport playing 的时序。本测试立即再次暂停，没有 firstAdvancingFrame 记录符合设计；不能把 32ms 与 Build 51 的 151ms playToFrame 比较，也不能宣称首帧／首次加载变快。准备阶段 seek 已暖缓冲，play 请求 loaded range 均 covered，loadedAheadSeconds 为 1.926／4.662／4.556，不代表冷缓存、磁盘命中或 CDN 速度。

## 下一步

保留当前 Build 52，不要求再跑十二分钟旧计划。优先在同一版本补实际画面和声音、横屏／竖屏切换、返回列表后重进，以及后台再回前台的短人工验收；若出现闪退、黑屏、自动播放或有声无画，保留具体动作／时刻并采集对应日志，再定向修复。耳机／系统中断和首次加载仍待专项采样。

当前源码 `1b77a638628eeef78a61123e51d61125e7f14141`，分支 `codex/pause-boundary-short-test-build52`；分析轮开始 HEAD `daa4d2946b03809b9d157ca7ea0ebf0a4bffbcce`。本轮仅文档提交，不合并 PR。
