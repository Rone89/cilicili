# 开发接续状态

更新时间：2026-11-02（Asia/Shanghai）。每轮工作结束后更新本文的完成内容、待办、测试结论、分支和提交号。

## 分支与工作区

- 仓库：https://github.com/Rone89/cilicili
- 当前分支：`codex/rapid-recovery-and-keyboard-build50`；从 `codex/seek-intent-and-paused-watchdog-build48` 接续，保留原分支和 PR #64 不合并。
- 本轮基线／已核实远端 HEAD：`8f7070c9622c6729c7f39a97d8e9be12ab103b60`。
- 接续工作树：`/Users/rayc/Desktop/cilicili-build48`。
- 原工作树 `/Users/rayc/Desktop/ccswift` 留在 `main`（`adf2995`），保留原有 3 个修改文件和未跟踪的 `docs/local-main-update-analysis-2026-10-06.md`。没有 stash、覆盖或混入这些改动。
- [PR #64](https://github.com/Rone89/cilicili/pull/64) 为开放的草稿 PR，未合并。用户已授权下一步整理提交并跑完整 CI；本轮仅推送新的 Build 50 分支并开草稿 PR，不合并。
- 当前开发版本为 1.1.1 / Build 50，新增 30 次／schema 3 快速操作计划和 UI 修复，验证与交付进行中。Build 49 首轮真机已确认暂停命令约 5ms；Build 50 真机结论仍待报告。不开发评论 IP 显示。

## 已完成

- 阅读 AGENTS.md、build-cache、自动恢复测试及重叠恢复修复文档和 PR #64 说明。
- 检查本地改动后 fetch 远端，在独立工作树检出上述分支，HEAD 与用户给定提交一致。
- 继承 Build 48 已实现的连续 seek 意图保持、旧请求隔离、暂停 seek watchdog 修复与 schema 2 耗时分解；首轮真机 21/21 observed，控制流异常未复现，版本间量化性能收益仍未证实。
- 在 AGENTS.md 引用本文并要求后续每轮更新。
- 已实现 [Build 49 非阻塞音频会话停用](playback-audio-session-build49.md)：把停用系统调用移到工作队列，共享激活入口等待在途停用并重查所有权／引擎代数；pause、后台、导航、stop 和 source 替换使旧请求无效。保留音频释放策略和帧／音画恢复保护。异步停用计时捕获原暂停 ID，报告说明已更新。首轮真机确认同步暂停跨度明显下降，整体恢复速度没有一致提升证据。
- 本轮本地兼容修复（已收纳于 Build 50 本地提交）：`SearchAPIProviding` 显式声明 `nonisolated`，解决 Xcode 27.1 测试编译阻断。Swift 默认隔离规则参考 [SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)。
- Build 49 阶段的本地变更现收纳到 Build 50 提交，最终代码提交号及 CI 结论见本文最新轮次。CI #151 不覆盖这些新改动。
- 2026-11-02 后续报告分析轮：收到并校验 Build 47 / schema 1 真机报告（runID `27A61EBA-0B5F-43B0-8B05-B90A2A63F088`），完成 [基线分析](playback-recovery-build47-device-baseline-2026-11-02.md)。21 次中 20 observed、1 timeout；连续拖动失败时最终目标从 playing 变为 paused，暂停拖动三次均出现约三秒后的同 ID 重复 seek 记录。本轮仅增加分析文档和原始报告本地副本，没有修改代码、重跑构建或测试；分支及 HEAD 不变，文档尚未提交。

## 环境与构建约束

- 当前 Xcode：27.1，`/Applications/Xcode.app/Contents/Developer`。
- 唯一允许的本地测试模拟器：iPhone 18 Pro Max / iOS 27.0，UDID `F0B4287D-8633-4CC1-B7C2-0A37F353FE7C`；检查时关机，由 Xcode 测试流程启动，不创建或切换其他模拟器。
- 跨工作树复用原仓库的 `/Users/rayc/Desktop/ccswift/build/DerivedData/Xcode-27`，通过原仓库 `Scripts/build-cache.py run --` 持锁；不创建任务专属永久缓存。
- 原仓库包装脚本将 cwd 切回原仓库，因此项目和 xcresult 必须使用接续工作树的绝对路径。首次误用相对路径的编译已停止，不计作 Build 48 验证。
- 原则上不修改项目签名、描述文件、bundle ID 或发布设置。2026-11-02 用户另行授权使用桌面 18pm 证书签名并安装到其 iPhone；本轮只重签 CI 产物，不修改项目配置或重新构建。

## 测试结论

- 已核实：[CI #151](https://github.com/Rone89/cilicili/actions/runs/41349593879) 对基线提交成功。
- PR 记录：1209 单元、141 UI、12 交互测试通过；照片素材预检曾超时一次，自动重试通过。此为远端历史结果，不冒充本轮本地结果。
- Build 49 本轮本地：13 项脚本测试全部通过；针对性 62 项全部通过；全量单元 xcresult 核对共 1215，1215 通过、0 失败、0 跳过。使用 Xcode 27.1、规定的 iPhone 18 Pro Max / iOS 27.0，共享 Xcode-27 缓存，串行执行。
- Build 48 接续首轮历史：单元共 1209，1206 通过、1 失败、2 跳过（跳过原因分别为受限网络禁用 parallel range fallback 和 startup hedging）；并非 Build 49 当前结果。
- 本轮重点 UI 共 14（CI 的 12 项交互 + 2 项恢复页面），12 通过、2 失败；恢复页面两项均通过。未重跑完整 141 项 UI。
- 历史 UI 失败已定位：评论用例错误要求英文独立 a/A 键，中文九宫格其实已恢复；搜索取消第 43 行失败是未恢复“大家都在搜”，先前误记为等待键盘消失失败。Build 50 评论用例改用原生 space 键与真实输入断言，已回归通过；搜索触摸日志进一步确认 principal 标题区域外的 Cancel 未命中，已改为自适应原生标题分配宽度并覆盖整行手势排除，独立取消回归通过、最终搜索组回归执行中。
- xcresult 同时记录主线程音频会话调用可能阻塞 UI，以及视图更新期间发布状态的运行时警告；仅记录观察，未据此认定为真机恢复延迟原因。
- 原工作树的已跟踪 diff 和 porcelain 状态均与接续前逐字节一致。
- 本地 Release：使用原仓库持锁包装脚本执行接续工作树 `Scripts/build-release-unsigned-ipa.sh`，成功。核验版本 1.1.1、Build 48、bundle ID `cc.bili`、最低 iOS 26.1，无 embedded.mobileprovision 或 _CodeSignature 文件。
- Build 48 本地验证包历史 SHA-256：`81be5dc5bae80f4858f21d6f2c69468b8a23602cf30102c563da5c3230a0c006`。它包含本地网络协议隔离修复，不等同 CI 的 Build 48；其常规 Release 输出和元数据路径现已由 Build 49 覆盖，不能按该历史校验值读取当前输出。CI 原始 Build 48 仍保留在 `build/ci-build48/`。
- 原样基线在 Xcode 27.1 编译失败：`SearchAPIStub` actor 无法遵循被默认推断为 MainActor 的 `SearchAPIProviding`。已给网络协议显式添加 `nonisolated`，与现有 nonisolated `BiliAPIClient` 和 actor 测试替身一致；未更改播放器。修复后的全量本地单元测试已执行 1209 项：2 项因网络策略主动跳过，1 个用例触发 2 条断言失败，整体退出 65。失败用例 `AVPlayerStartupPathOptimizationExperimentTests/testStartupPackagePrebuildReturnsImmediatelyWhenWarmupWaitIsZero` 首次返回 missing（预期 deferred），433ms（预期 <250ms）；单独复测整个类仍失败，耗时 219ms 已满足门槛，但仍返回 missing。日志明确记录 `mediaWarmupBudget action=skip reason=constrainedNetwork`，生产策略拒绝后台预热；当前用例依赖主机网络环境。本轮不修改预热策略或放宽断言。
- 已收到 Build 47 基线：暂停 5/30/120 秒的 playToFrame 中位数分别 161/137/143ms；nearby/distant seek 恢复 total 中位数分别 1047/1083ms；连续 seek 为 2 observed、1 timeout。observed 不等于性能通过，schema 1 无法分解约 732ms 的额外暂停开销。详细口径、记录关联和限制见基线分析文档。
- 已收到并逐条校验 Build 48 / schema 2 真机报告（runID `CE0673F5-9896-454D-BB4F-E616E715A55A`）：21 observed、0 timeout。连续 seek 三次均最终 seekPlaying、同 ID seekReveal/recovered=true；暂停 seek 三次各一条记录且状态检查通过，未复现旧版约三秒的重复 seek。仅确认本轮未复现，不能外推所有场景。
- 新报告定位：9 次普通暂停命令中位数 635.8ms，同 ID 音频会话停用中位数 630.7ms，逐次占比约 99%；playToFrame 中位数 157ms（105–161ms）。优先调查同步停用音频会话开销及 pause/play 竞态。
- 两轮非严格性能对照：Build 47 为 AV1／华为云，Build 48 为 HEVC／CDN 自动选择且独立应用容器；不能量化宣称版本加速，首次加载、音画输出与冷缓存仍待额外验证。详细结果见 [Build 48 真机分析](playback-recovery-build48-device-analysis-2026-11-02.md)。

## 真机验收与报告采集

1. 核对设备中版本 1.1.1（48）。现有 [CI Release 产物](https://github.com/Rone89/cilicili/actions/runs/41349593879/artifacts/13100862005) 为未签名 IPA，PR 记录 SHA-256：`8d04314741f7dc43fdb914eaa5cfb7e1effac2c7061c7a0f23aa9a803a3a98d4`；已下载并复核该文件的 SHA-256、版本和 Build。
2. 使用至少五分钟的录播，等首帧出现，进入“更多播放设置 → 自动恢复测试 → 开始”。保持前台，正常约十二分钟，自动完成七种情景各三次（21 次）。不需逐项手动计时。
3. 完成后复制／分享最终 JSON；也可从“我的 → 开发者与诊断 → 播放与网络诊断 → 自动恢复测试报告”取回。只保留最新一轮，下一轮前先保存报告。
4. 一并记录机型、系统、网络类型、视频、画质／编码和速度、是否中断，以及可见黑帧、画面冻结或有声无画等观察。保持 Build 47/48 对比条件一致。
5. 收到报告后分别比较 observed、timeout、interrupted 等结果，按情景分析首帧／恢复分布；区分 pause/play/seek 同步命令、pauseHold 和实际恢复耗时，检查 audio-session deactivation 占比、最后目标关联、paused seek 是否发生早期重试。缺失证据不得记为零或通过。

## 本地证据与复跑

工作目录为 `/Users/rayc/Desktop/cilicili-build48`，证据保存在被 Git 忽略的 `build/logs/`：

- `build48-unit-final.log/.xcresult`：原样基线在 Xcode 27.1 的编译失败。
- `build48-unit-compatible.log/.xcresult` 与 `build48-unit-summary.json`：兼容修复后的完整单元结果。
- `build48-startup-retest.log/.xcresult`：启动测试类复测结果。
- `build48-focused-ui.log/.xcresult` 与 `build48-focused-ui-summary.json`：14 项重点 UI 结果。
- `release-unsigned-ipa.log`、`build48-release-wrapper.log`：本地 Release 构建证据。

复跑时继续通过 `/Users/rayc/Desktop/ccswift/Scripts/build-cache.py run -- xcodebuild` 持锁，并使用 `-project /Users/rayc/Desktop/cilicili-build48/bili.xcodeproj -scheme bili -configuration Debug -destination platform=iOS\ Simulator,id=F0B4287D-8633-4CC1-B7C2-0A37F353FE7C -parallel-testing-enabled NO`；单元选择 `-only-testing:biliTests`，UI 选择见 CI 的 interaction-regression 列表及 `VideoDetailFlowUITests` 的两项 `testAutomaticRecoveryTest...` 方法。为每次复跑指定新的绝对 `-resultBundlePath`，不要复用已有 xcresult 路径。

## 待办

- Build 49 全量单元 1215 项、5 项重点播放 UI、Release、签名安装及启动均已验证；首轮真机报告 21 observed，暂停命令中位数 5.1ms，12 次后台停用均成功。下一步补充在途快速操作、后台／导航和音画体验证据。此前 2 项键盘 UI 未复跑，失败仍待独立调查，本轮不声称完整 141 项 UI 已通过。
- 后续修复启动预构建用例对真实网络环境的依赖，使用可控环境验证排队与零等待分支；保持受限网络策略。
- 本地 unsigned Release 构建验证已完成；如后续交付包含本轮源码修复的新真机包，先按发布规范递增 Build，重新走验证，不复用 48 作为新交付。
- Build 47/48/49 首轮报告均已归档分析。Build 49 同步暂停中位数约 5ms、后台停用约 106ms、playToFrame 约 150ms；优先补在途快速暂停／播放和后台／导航证据。维持现有恢复窗口，不把同步命令变短认定为恢复整体加速。
- 如需量化版本性能收益，先统一编码、CDN 和设置后重新采样；当前两轮不能作为严格对照。
- 后续每轮结束更新本文，明确本地新增提交（如有）与尚未提交的文件，不把基线 SHA 当作新改动的提交号。


## 2026-11-02 Build 48 真机安装轮

- 授权范围：用户明确要求使用桌面 `18pm证书` 的签名材料，把 Build 48 安装到其 iPhone。不在文档或配置保存证书密码；匹配身份已在钥匙串可用，本轮无需重新导入。
- 来源：CI #151 / artifact `13100862005`，下载至 `build/ci-build48/`，IPA SHA-256 已核对为 `8d04314741f7dc43fdb914eaa5cfb7e1effac2c7061c7a0f23aa9a803a3a98d4`。使用原 CI 二进制，没有混入本地 `SearchAPIProviding` 兼容修复。
- 设备：已配对并连接的 iPhone 18 Pro Max（设备名 RCe2027），iOS 27.2，机型 iPhone19,7；已确认桌面描述文件包含该设备，且证书身份有效。
- 安装：通过现有 `Scripts/sign-install-unsigned-ipa.sh` 签名和安装成功，`codesign --verify --deep --strict` 通过。描述文件固定 App ID，脚本将重签副本的 bundle ID 设为 `app.bamboo2779.brussels691`，未修改源码项目的 `cc.bili`。
- 安装后设备应用列表已核验：新应用 cilicili 1.1.1 / Build 48；XcodeBuildMCP 已成功启动新应用（PID 68224）；原 `cc.bili` 的 Build 47 仍保留。二者独立容器，旧登录和设置不会自动迁移，真机对比前需手动保持设置一致。
- 签名安装日志：`build/logs/build48-sign-install.log`；签名应用：`build/debug-resigned-install/bili-release-unsigned/bili.app`。
- 本轮没有新建构建、运行自动恢复试验或验证性能；下一步在新 Build 48 中运行自动恢复测试，保存 build=48 / schemaVersion=2 的报告。旧 Build 47 图标仍在，注意选择新应用。
- 分支仍为 `codex/seek-intent-and-paused-watchdog-build48`，HEAD 仍为 `8f7070c9622c6729c7f39a97d8e9be12ab103b60`；本地改动及本文仍未提交，未推送或合并 PR。

## 2026-11-02 Build 48 真机报告分析轮

- 完成：读取并保留原始 schema 2 报告，核对 21 个试验、sampleBuild=48、最终目标 ID 与播放模式、12 次音频会话停用关联和 9 次暂停时间分解；完成 `docs/playback-recovery-build48-device-analysis-2026-11-02.md`。
- 验证结论：本轮 21 observed；连续拖动丢失意图和暂停拖动旧 watchdog 重复 seek 均未复现。尚未确认所有环境下完全消除，observed 不等于音画／性能验收通过。
- 新发现：同步显式暂停开销约 0.63 秒，音频会话停用占约 99%；编码和 CDN 与 Build 47 不同，不能计算版本加速比例。
- 待办：优先调查音频会话停用路径与所有权竞态；保持音画保护，再决定最小修复和新 Build。此前本地测试失败仍保留待办。
- 本轮没有改代码、构建、安装、提交、推送或合并。分支 `codex/seek-intent-and-paused-watchdog-build48`，HEAD `8f7070c9622c6729c7f39a97d8e9be12ab103b60` 不变；分析文档及先前本地改动仍未提交。

## 2026-11-02 Build 49 开发与安装轮

- 完成内容：实现 `PlaybackAudioSession` 共享停用／激活顺序管理；系统停用调用离开主线程，合并在途重复停用，激活等待后校验最新意图、停止状态和播放器所有权。保持同步暂停 AVPlayer、notifyOthersOnDeactivation、后台与导航策略，不改变帧和音画保护。听视频激活入口也纳入等待；异步计时绑定提交时的原暂停 ID。版本 1.1.1 / Build 49。
- 新增验证：4 项共享音频会话竞争／失败测试、1 项真实 AVPlayer 在途停用时后台暂停拒绝旧播放的测试、1 项异步计时不串到新暂停的测试。针对性 62/62、全量单元 1215/1215、重点播放 UI 5/5、脚本测试 13/13 全通过，均 0 失败；全量单元 0 跳过。此前受限网络启动用例本轮通过，但环境依赖仍待改进。此前键盘 UI 两项本轮未复跑。
- 环境：Xcode 27.1，已有 iPhone 18 Pro Max / iOS 27.0，原仓库 Xcode-27 共享缓存和包装脚本串行构建；没有清缓存或创建模拟器。初轮针对性测试结束后诊断收集卡住，仅终止 `simctl diagnose` 子进程，之后 xcodebuild 退出 0；日志及 xcresult 保留。全量单元和 UI 正常退出 0。
- Release：通过现有 `Scripts/build-release-unsigned-ipa.sh` 成功构建。核对 1.1.1（49）、原始 bundle ID `cc.bili`、最低 iOS 26.1，未签名包无描述文件／签名目录。SHA-256：`0b7e0f5c3d5c6533b794a134c7fa9f29266fa38de6e908a13a8ce68708ae4fa8`。
- 产物：`build/release-unsigned-ipa/bili-release-unsigned.ipa` 和 `build-info.json`；元数据明确 sourceDirty、本地源码基线 SHA、相关源码文件 SHA-256、工具链与测试结论。这是本地 Build 49，未运行新的远端 CI，不冒充 CI 产物。
- 安装与启动：沿用用户授权的桌面 18pm 签名材料和现有脚本，签名校验通过，覆盖更新 `app.bamboo2779.brussels691`，没有执行卸载或清容器。设备应用列表已核对 1.1.1 / Build 49；已成功启动（PID 68636）。设备为同一 iPhone 18 Pro Max / iOS 27.2。
- 证据：`build/logs/build49-audio-focused.*`、`build49-unit.*`、`build49-playback-ui.*` 及各 summary.json；`build49-release-wrapper.log`、`release-unsigned-ipa.log`、`build49-sign-install.log`、`build49-device-apps-after.log`。原 main 工作区 diff 再次与接续前逐字节一致。
- 待办／真机结论：请在新 Build 49 运行自动恢复测试。比较 pauseCommandMilliseconds、后台 audioDeactivationMs 和 playToFrame；快速暂停／播放及切后台要确认旧请求不误恢复。系统后台调用仍可能约 0.63 秒，不能把它与暂停命令相加或只因暂停命令变短就宣称恢复加速。匹配 Build 48 的编码、CDN 和画质条件；目前没有 Build 49 真机性能报告。
- 分支仍为 `codex/seek-intent-and-paused-watchdog-build48`，Git HEAD 仍为 `8f7070c9622c6729c7f39a97d8e9be12ab103b60`；本轮改动及先前文档／兼容修复均未提交。未推送或合并 PR。

## 2026-11-02 Build 49 真机报告分析轮

- 完成：解析并保存 runID `C2750928-9B1B-4799-8DFB-724EB93472B7` 的 Build 49 / schema 2 原报告，核对全部 21 个试验及 12 个停用事件的 ID、成功标记、普通暂停跨度和连续最后目标。见 [Build 49 真机分析](playback-recovery-build49-device-analysis-2026-11-02.md)。
- 验证结论：21 observed、0 timeout；同步暂停命令中位数从 635.8ms 降到 5.1ms（4.3–7.6ms），后台停用中位数 106.0ms 且 12 次均成功。playToFrame 为 96–152ms、中位数 150ms；连续拖动和暂停拖动旧异常未复现。
- 限制：两轮 CDN 选择不同，暂停恢复分组有快有慢，不能宣传视频加载或恢复整体加速约 99%。本轮普通暂停至少五秒、pausedSeek hold 约两秒，停用均早已完成，不覆盖在途快速连点或切后台竞争。继续保留音画和帧保护。
- 待办：保留 Build 49，补快速操作及后台／导航／音频中断的真机证据；随后处理测试环境依赖、键盘 UI 和提交整理。无需因本轮正常采样而改恢复窗口。
- 本轮只更新分析和开发记录，没有代码改动、构建、测试、安装、提交或推送。分支 `codex/seek-intent-and-paused-watchdog-build48`，HEAD `8f7070c9622c6729c7f39a97d8e9be12ab103b60` 不变，先前源码和文档改动仍未提交。

## 2026-11-02 Build 50 快速操作与 UI 回归轮

- 分支：`codex/rapid-recovery-and-keyboard-build50`；已提交 `04c89ab5c5c8d81bca34ec99b5325a6d55594b26`，收纳 Build 49 非阻塞停用、快速操作 30 次／schema 3、兼容修复和前几轮文档。随后补充搜索工具栏命中区域修复；最终发布提交以远端草稿 PR 为准，原 PR #64 不合并。
- 完成：新增立即暂停／播放、20ms 连续切换后播放／暂停三种情景；记录命令时间线和在途停用证据，最后播放必须匹配最终 play ID，最终暂停等待停用结束并持续观察一秒。缺少竞争证据标为 missingEvidence，旧报告仍兼容。
- 已验证：首轮全量单元 1220/1220、脚本 13/13；20ms 最终间隔随后通过重点单元 31/31。评论原生输入法测试通过；14 项重点 UI 首轮 13/14，剩余搜索取消在工具栏布局修复后独立回归通过。最终搜索全组＋评论回归执行中，完整 CI 和 Release 尚待执行完成。
- 原因与修复：导航栏 principal 标题会绘制到原生点击边界之外，触摸命中导航容器；保留 principal 搜索行，idealWidth/maxWidth 接受原生较小宽度，并将行外点击排除范围包含 Cancel。尝试 topBarLeading 虽能取消，但整组回归发现挤压筛选和我的页，已弃用。评论旧测试要求英文 a/A，现用 native space 键和真实追加输入断言，产品输入法不变。
- 待办：完成最终搜索回归、发布新分支草稿 PR 并跑完整 CI、下载并核验 Build 50 未签名产物、沿用授权证书原位更新 iPhone，再收集 build=50/schema=3/plannedTrialCount=30 报告。Build 50 真机性能、实际音画、后台／导航／耳机与音频中断仍待验证。
- Git HTTPS 推送缺少本机凭据，改用已认证 GitHub 连接器创建同内容 Git tree/commit 并快进新分支；不改动原工作树及其凭据配置，不使用强推。

- 发布补充：草稿 [PR #65](https://github.com/Rone89/cilicili/pull/65) 已创建，首个远端提交 `ebff3689efb31b9ffd50fc98ac154967462846af`，CI #152 正在执行。随后发现搜索 leading 布局导致其他场景回归，改回 principal 并采用自适应宽度，待最终提交与完整 CI 重新确认；不可使用 #152 的 Release 交付最终源码。
- 本机 github.com Git 传输连续连接失败；api.github.com 可用。通过公开 Git commit API 元数据重建对象、逐字节 SHA-1 核验得到远端相同 commit，本地分支已对齐 `ebff3689`；原两次本地提交保存在 `codex/build50-local-backup`。没有修改全局网络／Git 配置。
