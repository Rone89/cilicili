# 开发接续状态

更新时间：2026-11-08（Asia/Shanghai）。每轮工作结束后更新本文的完成内容、待办、测试结论、分支和提交号。

## 分支与工作区

- 仓库：https://github.com/Rone89/cilicili
- 当前分支：`codex/coin-401-auto-like-build54`，从 Build 53 诊断提交接续投币／点赞修复；Build 50 分支 `codex/rapid-recovery-and-keyboard-build50`、草稿 PR #65 和原 PR #64 保留，不合并。
- 最初接续基线：`8f7070c9622c6729c7f39a97d8e9be12ab103b60`；Build 51 本轮基线：`317f89b02ccdb81f8cf4dff8afe7e125199720e2`。最新源码备份提交见本文件末尾。
- 接续工作树：`/Users/rayc/Desktop/cilicili-build48`。
- 原工作树 `/Users/rayc/Desktop/ccswift` 留在 `main`（`adf2995`），保留原有 3 个修改文件和未跟踪的 `docs/local-main-update-analysis-2026-10-06.md`。没有 stash、覆盖或混入这些改动。
- [PR #64](https://github.com/Rone89/cilicili/pull/64) 为开放的草稿 PR，未合并。用户已授权下一步整理提交并跑完整 CI；本轮仅推送新的 Build 50 分支并开草稿 PR，不合并。
- 当前开发及手机版本：1.1.2 / Build 57，已原位安装并启动。Build 54 按用户选择投币时自动点赞。用户确认未点赞时 `-401 非法访问`，先点赞再投币成功；用户确认 Build 54 真机投币已正常。Build 52 的暂停边界及三组短验收已收集。不开发评论 IP 显示。

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

- 最终源码：`317f89b02ccdb81f8cf4dff8afe7e125199720e2`，本地与远端 tree 一致；CI [#153](https://github.com/Rone89/cilicili/actions/runs/41449548952) 已实际开始，#152 已自动取消。原本地补充提交保存在 `codex/build50-width-local-backup`。
- 最终本地搜索全组 13/13 通过、0 跳过（`build/logs/build50-search-fitting.log/.xcresult` 和 summary.json），含取消、滚动、反复提交、详情返回、筛选、行外点击、我的页及无按钮时宽度回收。评论原生键盘在此前最终组 1/1 通过；该组的其他搜索失败对应已撤回的 leading 布局，不能合并算成最终失败或隐藏历史。原 main 已跟踪 diff 再次逐字节核对未改变。
- 设备 RCe2027 / iOS 27.2 当前连接，签名安装仍待最终 CI 产物。此后本状态文档的更新为本地验收记录，不改变已提交源码或声称最终 CI 已完成。

- CI #153 阶段结果：Release 成功；单元 1220 个唯一用例最终全部通过、0 跳过。`DeterministicAVPlayerTransportTests/testGeneratedDASHSourcePlaysThroughLocalHLSBridge` 首轮等待 AVPlayer item ready 超时，产生两条断言失败，Xcode 自动第二次迭代于 9.706 秒通过；合计 1221 次迭代，不误写成 1221 个独立用例或首轮全绿。首次超时原因尚未确定，不能直接归因于播放器生产逻辑或宣称仅环境问题。日志已保留 `build/ci-build50/verification/unit-log/bili-tests.log`。
- CI artifact `13144841508` 下载与 ZIP digest 核验成功；未签名 IPA 为 1.1.1（50）、`cc.bili`、最低 iOS 26.1，无签名／描述文件。IPA SHA-256：`9f1ac9e04da8ac45a47c23b409fa9d8684ca02f171fbdb4406ba9a56154d2cde`。构建记录的合成 PR commit `88679c3f8bd7d6e2985fd91e49a013fb117f4bca` tree 与源码提交 `317f89b` 的 `7cdff79652d22f4c8a69ffd7d049c29fd9be915f` 完全一致；GitHub 的测试合成提交不代表 PR 已合并。
- 产物与机器可读校验位于 `build/ci-build50/`、`verification/validation.json`（Git 忽略）。UI 分片、交互、签名安装和 Build 50 真机报告仍待完成。

- Build 50 真机交付：沿用用户授权桌面签名材料和既有脚本，签名校验成功，原位覆盖更新 `app.bamboo2779.brussels691`，未卸载或清容器。设备列表核验 1.1.1（50），成功启动 PID 69451。签名日志 `build/logs/build50-sign-install.log`，设备证据 `build50-device-apps-after.json`。本次在单元、Release、本地重点 UI 通过后先行安装以便采样；远端完整 UI 仍在运行，不能据此写成全部 CI 已绿。待用户运行新版 30 次／schema 3 报告，Build 50 真机性能尚未验证。

- CI #153 交互组 12/12 通过、0 跳过、无失败后重试，已核对逐用例日志，包含搜索取消与评论原生键盘两项旧失败用例。4 个完整 UI 分片仍在运行。
- CI 的 swift-format 为既有非阻断检查；日志包含格式规则提示，不能把 job success 等同于源码格式完全无提示。本轮未扩大范围重排历史源码。

- CI #153 首轮最终 6/7 jobs 成功：完整 UI 为 140/141 最终通过，搜索组 13/13 全通过。唯一最终失败 `CommentActionFlowUITests/testReplyActionOpensComposer` 在第 15 行 `app.launch()` 阶段两次失败（Xcode 启动超时、target pid 0 无后台断言），回复操作尚未执行；不能把已安装或搜索通过当作完整 CI 已通过。
- 另有 `AccountLibraryManagementUITests/testCommentDraftReturnsAfterHostRecreationWithoutCrossingContentTargets` 首轮 AX focused-app 属性查询超时、重试通过；RootTabScroll 的 minimized／Reduce Motion 两项首轮超时后重试通过。三份其他 UI 分片分别 36/35/35 全通过。
- 已请求仅重跑 ui-4（CI #153 attempt 2，job `125318440221`），其余成功结果保留，源码仍为 `317f89b`。同一回复用例本地独立复测 1/1 通过（`build/logs/build50-reply-launch-check.*`），Xcode 27.1／规定 iOS 27.0 模拟器／共享缓存，未改代码或放宽断言。首次失败日志保留 `build/ci-build50/verification/ui4-attempt1-log/bili-tests.log`，远端完整收尾仍待重跑结果。

## 2026-11-02 Build 50 报告与本地 Build 51 轮

- 用户新分工已写入 `docs/local-device-development.md` 并由 AGENTS 引用：Mac 修改／测试／日志分析，Xcode+iPhone 本地构建直接安装，GitHub 保存提交／备份并在重要版本云端回归。已有 Build 50 云端重跑继续，但不阻塞本地开发，不为 Build 51 日常迭代再跑整轮云端。
- 分支已从 `317f89b` 切为 `codex/stale-player-observation-build51`，HEAD 暂仍 `317f89b02ccdb81f8cf4dff8afe7e125199720e2`，本轮源码与文档尚未提交。开发版本 1.1.1（51），手机目前仍为 Build 50。
- 收到 Build 50 schema 3 原报告：30 次／29 observed／1 failed，最后一次 rapidTogglePaused keptPaused=false。15 条快速 play 均有 pending 在途证据，23 条音频停用均成功；前 21 个既有情景通过。详细校验、时序和性能口径见 `docs/playback-recovery-build50-device-analysis-2026-11-02.md`。
- 可控复现：真实 AVPlayer 同一 MainActor 内 play→pause，实际 rate=0 但旧 KVO 仍发布 playing 并恢复意图；新增测试在旧代码稳定失败。仅重读 timeControlStatus 仍失败，补充实际正速率校验后独立回归通过。完整本地单元正在执行；补充暂停失败时 isPlaying／wantsPlayback／pending 独立字段，不放宽失败条件或修改音画保护。
- 待办：完成 Build 51 本地单元、直接签名构建 `.app`、原位安装启动、提交备份，再采集新版真机报告。Build 50 原报告不能证明实际出声或唯一根因，Build 51 真机效果尚待验收。

- Build 51 验证与安装已完成：全量本地单元 1222/1222、0 失败、0 跳过；新 KVO 回归由旧代码两个断言失败变为独立及全量通过，新增意图错误／实际播放独立诊断回归通过。最终源码只做观察值刷新与当前 rate>0 核验，没有新增延时、恢复窗口或放宽失败条件。
- 使用 XcodeBuildMCP 和原共享 Xcode-27 缓存串行完成本地签名 Debug（40.3 秒）及 Release（110.2 秒）构建，签名参数仅为命令行覆盖。实际安装 Release 以保持与旧采样配置接近。直接安装 `.app`，没有制作／下载 IPA，没有改项目 bundle ID 或签名发布设置。
- 设备核验 1.1.1（51）／`app.bamboo2779.brussels691`，原位更新成功、启动 PID 69933。应用可执行文件 SHA-256 `838bf878379a664fe5eb35b885261c6e6afc0e91fc97ba008dea891a19218c4c`，签名深度校验通过。`build/logs/build51-device-build-info.json` 记录源文件 hash、配置、构建基线和后续备份提交；`build51-device-apps-after.json` 为设备证据。
- 本地测试证据：`build51-stale-kvo-before.*`（确定性失败）、`build51-stale-kvo-after.*`（仅刷新仍失败）、`build51-stale-kvo-rate-check.*`（补充正速率验证后通过）、`build51-unit.*`／`build51-unit-summary.json`（最终 1222 通过）。MCP 设备构建日志在用户 XcodeBuildMCP workspace 日志目录，构建有既存 Swift 隔离等警告，未扩展本轮修复范围。
- 当前授权 profile 的 get-task-allow=false，可签名安装并收集日志；直接 LLDB 断点附加需要允许调试的开发 profile，未擅改权限。
- 原 main 工作区 diff 再次与接续前逐字节一致。Build 50 首轮 UI4 完整日志已归档；其 256MB 可读诊断 ZIP 在下载时超时，`.zip.partial` 不可作为完整证据，完整远端 artifact 为 `13147406557`，首次失败日志不依赖该 ZIP。新分工下日常开发不等待云端；下一步运行 Build 51 的 30 次真机试验，重点复验 rapidTogglePaused 三次及实际声音／画面，另补后台／导航／耳机、中断和横竖屏验收。

- Build 51 源码及本轮报告／工作流文档已提交并备份：`aa562916e76d9a54c14d6805661c158aca6e4fed`，分支 `codex/stale-player-observation-build51`。通过连接器发布 Git tree 并核对与本地一致，GitHub API 原始 commit 元数据重建后 SHA 逐字节相同；本地分支已对齐。设备实际构建时以 `317f89b` 加本轮工作树源码完成，后续备份的三个应用源文件 hash 均与实际构建记录一致，不冒称构建时 HEAD 已是新提交。
- 仅作分支提交备份，没有创建新的 Build 51 PR、启动 Build 51 完整云端 CI、合并或强推。当前收尾记录为随后文档提交，应用源码提交保持上述 `aa562916`；Build 50 既有云端重跑仍待最终结果。后续每轮继续更新本文。

## 2026-11-02 Build 51 真机报告分析轮

- 分支 `codex/stale-player-observation-build51`，本轮开始 HEAD `4040b651948a4628b631ea4d6dbabfcd1e638279`，应用源码仍为 `aa562916e76d9a54c14d6805661c158aca6e4fed`；本轮只归档、校验和写文档，未改播放器、构建、安装或新开云端回归。
- 收到 runID `65833B09-22BE-46EB-BACD-7D0A30D863FA` 的 Build 51 schema 3 报告：30/30 observed，无失败／超时／缺证。ID、情景次数、sampleBuild、checks、六次最终播放帧 ID、15 条 pending play、21 条成功停用、连续 seek 最后目标和 pausedSeek 单条记录均校验通过。
- 已验证：本轮三次 rapidTogglePaused 均 keptPaused=true，Build 50 旧失败未复现。限制：三次最后暂停前 pending 都为 true，未覆盖 Build 50 失败时 pending=false 的停用结束边界；不能认定所有竞态真机验收完成。详见 `docs/playback-recovery-build51-device-analysis-2026-11-02.md`。
- 性能：普通暂停命令中位数 4.66ms、playToFrame 151ms，仍同一量级；立即恢复 347ms、反复切换后播放 266ms，比 Build 50 本轮更慢，后台停用中位数 181ms。工具链和系统状态等未受控，不直接认定版本加速或退化，不缩短恢复保护窗口。
- 待办：优先补“停用完成后，同一主线程周期 play→pause”的可控自动真机场景，明确记录覆盖条件；随后补实际音画、后台／导航、耳机／中断、横竖屏及首次加载。本轮不要求用户再次重复整套旧计划来碰时序，也不新建 Build。
- 云端收尾：CI #153 attempt 2 已 completed/success，ui-4 重跑 35/35、无失败后重试；其余六个成功任务保留，最终 1220 单元、141 UI、12 交互、Release 通过。首轮 launch／AX／RootTabScroll 超时与单元重试仍记录。该结果仅覆盖 Build 50 源码 `317f89b`，不冒充 Build 51 云端验证。
- 原报告与机器可读核验保存于 Git 忽略的 `build/device-reports/build51-65833B09.json`、`build51-analysis.json`；SHA-256 为 `0f86d02f71ddc9236505f162e50e81fe7a8e1e71910c6ac67af0f1535e893f05`。本轮文档随后提交备份，未合并任何 PR。

## 2026-11-02 Build 52 暂停边界短测轮

- 分支 `codex/pause-boundary-short-test-build52`，本轮基线 `037167c4bdae228160f6a481424e116461f0cfa5`。新增停用完成后的同周期 play→pause 情景，完整计划 33 次，新增三次短测入口。详见 [边界短测说明](playback-recovery-pause-boundary-build52.md)。
- 已实现：schema 4 记录计划类型及命令后实际播放／播放意图；只有停用完成、播放正状态和最终暂停保持均有证据才 observed。未知状态／未同步播放标记 missingEvidence，不放宽故障条件。播放器生产逻辑保持 Build 51，不新增延时策略。
- 本地已验证：针对性 34/34、全量单元 1228/1228，均零失败／零跳过。证据 `build/logs/build52-focused.*`、`build52-unit.*` 及 summary.json。重点 UI 首轮 1 通过／2 失败，两个停止／复制用例因列表报告行在屏幕外未找到结果；补充滚动后复跑 3/3、零跳过通过，包含计划数为三次、停止中断和复制成功，未删除或放宽原断言。证据 `build52-recovery-ui.*`（首轮）和 `build52-recovery-ui-scroll.*`（最终）。尚未取得 Build 52 真机报告，不能记为真机通过或性能改善。
- 已直接交付：Xcode 27.1／共享 Xcode-27 缓存串行签名 Release 构建 104.8 秒成功，签名深度核验通过，设备核验 1.1.1（52）、成功启动 PID 70198；原位更新，没有卸载或清容器。签名仅命令行覆盖，没有 IPA 下载／打包或新开完整云端 CI。既有 Swift 隔离等构建警告保留，未扩展范围修复。应用可执行文件 SHA-256 `791aa708dbace6d7c69a87e8b9aa224c0ba1938e8a082a1d865f51a9a332e266`，源码 hash／构建配置见 `build/logs/build52-device-build-info.json`，设备证据 `build52-device-apps-after.json`。
- 下一步：用户跑三次短测并发最终报告，再据缺证／失败字段决定是否还需定向采集。实际音画、首次加载、后台／导航、耳机／系统中断、横竖屏仍待真机验收。

- Build 52 源码及本轮测试／交付文档已提交并备份：`1b77a638628eeef78a61123e51d61125e7f14141`，分支 `codex/pause-boundary-short-test-build52`。GitHub tree 与本地一致（`8dea0d11889df2d94e2f7fb12494b880202ea8ee`），实际设备构建时的四个改动应用文件 hash 与该提交逐一一致；构建时基线为 `037167c` 加未提交源码，没有冒称构建时 HEAD 已是新提交。本记录随后做文档提交，应用源码保持上述提交。
- 原 main diff／porcelain 与接续前快照逐字节一致。仅新分支备份，没有合并／强推、没有创建 Build 52 PR 或发起 Build 52 云端回归。Build 50 CI #153 的成功不作为 Build 52 云端结论。真机目前仅验证安装启动，边界、实际音画及性能仍待用户报告。

## 2026-11-02 Build 52 真机报告分析轮

- 当前分支 `codex/pause-boundary-short-test-build52`，本轮开始 HEAD `daa4d2946b03809b9d157ca7ea0ebf0a4bffbcce`；应用源码仍为 `1b77a638628eeef78a61123e51d61125e7f14141`。本轮只校验、归档及更新文档，未改代码、构建、安装或重跑自动测试。
- 已验证：收到 schema 4／pauseBoundary 报告 `F788D232-E597-4FA5-9CF2-048BFA6833CF`，3/3 observed，零失败／超时／缺证。三次 play 和最后 pause 前 pending 均 false，命令后意图与实际引擎状态 false→true→false，五项 checks 全 true；六次停用均成功且 ID 归属正确。补齐 Build 51 首轮缺少的停用结束边界，旧暂停异常本轮未复现，不外推所有时序。
- 耗时：三次最后暂停命令 0.469／1.068／1.067ms；第二次后台停用 786.7ms 仍保持最终暂停，不能把后台长尾当成同步暂停阻塞。playToTransport 中位数 32ms，本短测没有首帧记录，不能与旧 playToFrame 直接比较或宣称整体加速。
- 详细结论与局限见 [Build 52 真机分析](playback-recovery-build52-device-analysis-2026-11-02.md)。原报告、断言脚本和机器可读分析存于 Git 忽略的 `build/device-reports/`；原始 SHA-256 `4335d3b72f184c3ce4f5a1a027d912d49193d27b587ae635b2dcbca5625ca11a`。
- 待办：保留 Build 52，优先补实际音画、横竖屏、返回重进、后台恢复的短人工验收；首次加载、耳机／系统中断仍待专项采样。出现异常再按动作／时刻取日志，当前没有依据新增性能修复或新 Build。本轮文档随后提交备份，不合并 PR，不新开云端回归。

## 2026-11-02 Build 52 音画／生命周期验收准备轮

- 分支 `codex/pause-boundary-short-test-build52`，本轮开始 HEAD `b6fe418a74800036296f9ee090fd0e67db0f9988`；应用源码保持 `1b77a638628eeef78a61123e51d61125e7f14141`，手机仍为 Build 52。本轮没有修改应用、递增 Build、安装或开启云端 CI。
- 已验证：使用规定的 iPhone 18 Pro Max／iOS 27.0 模拟器及原共享 Xcode-27 缓存串行执行现有生命周期 UI 用例，3/3、零失败／零跳过，覆盖后台返回、旋转中退出和全屏往返；这只证明 fixture 的 UI 结构／生命周期回归，不等于真机音画通过。证据 `build/logs/build52-lifecycle-ui.log/.xcresult` 和 summary.json。
- 自动取证已实测：直接从连接的 RCe2027 应用容器读取 `PlaybackRecoveryTests/latest.json`，与用户 Build 52／runID `F788D232-E597-4FA5-9CF2-048BFA6833CF` 粘贴报告逐字段一致；无需重新启动 App 或复制粘贴。系统 crash 目录三个 bili 文件均核对为 2026-10-31／Build 43／cc.bili，未将它们当成当前 Build 52 故障。查询未发现新的同名记录，不据此宣称绝无崩溃。
- 操作步骤、取证命令和结果边界写入 [Build 52 短验收指南](playback-build52-device-acceptance.md)。日志仅本地 Git 忽略目录归档；既有内存性能日志仍需用户在“启动链路性能日志”复制，应用持久化恢复报告不包含本轮人工动作记录。
- 待办：用户用当前版本完成播放中／暂停时横竖屏、返回列表重进、后台约十秒再返回，并反馈音画与状态；异常需动作／时刻和性能日志，若闪退则拉取对应新 crash。首次加载、耳机／系统中断继续待专项验证。现有 MCP 没有真机触摸／旋转能力，未为自动化更改签名／调试权限。
- 原 main diff／porcelain 再次与接续前快照一致。本轮只新增验收文档和状态记录，随后提交备份，不合并 PR。

## 2026-11-02 Mac 一键验收脚本轮

- 分支 `codex/pause-boundary-short-test-build52`，本轮开始 HEAD `756c544d98c98001877b239eef1aaf042d72006d`；手机／应用源码仍是 Build 52／`1b77a638628eeef78a61123e51d61125e7f14141`。用户明确选择 Mac 桌面双击脚本，真机触摸按提示完成；未修改 App、递增 Build 或重新安装。
- 已完成：`Scripts/device-acceptance.py` 及 `.command` 入口自动核验手机应用、留存报告／崩溃基线、持锁跑三项模拟器 UI、引导三组人工操作、按用户选择读取已复制的性能日志，再采集报告和新增同名 crash、保存 summary 并打开结果目录。桌面 `cilicili一键验收.command` 已建立，本机设备 ID 仅放本机入口／环境变量。操作说明已补到短验收指南。
- 结果每轮独立写入 Git 忽略的 `build/device-acceptance/`，不覆盖旧轮；保留错误／部分结果、未执行／未观察项及用户原始反馈。留存恢复报告明确不是人工生命周期验证证据；崩溃核对 bundle／Build，无新增文件不当成无闪退。没有上传任何设备数据。
- 已验证：3 项脚本证据回归通过；zsh 语法、桌面入口 `--help` 通过；真实手机 collect-only 取证通过。脚本端到端非交互执行成功，三项 UI 3/3，报告 runID 与已验证 Build 52 报告一致，人工三项和总结果保持 pending。证据 `build/device-acceptance/20261102-232904-f24zy6fv/`（采集）、`20261102-232932-jml163t7/`（全自动部分）及 `build/logs/oneclick-launcher-help.log`。
- 待验证：用户双击后按提示完成真机音画／横竖屏、返回重进、后台恢复，选择取回性能日志的交互路径也需实际使用确认；没有代填人工正常。脚本本轮验证不等于真机音画通过。首次加载及耳机／系统中断仍待专项采集。
- 原 main 改动核对不变。下一步交付桌面入口，收到 summary／异常日志继续分析；本轮脚本、测试和文档提交备份，不合并 PR，不新开云端 CI。

## 2026-11-02 一键脚本实机使用与反馈轮

- 分支 `codex/pause-boundary-short-test-build52`，本轮开始 HEAD `44e11d660698cab56a7167d1a5a4a764bf9d75cb`；应用源码／手机版本仍为 `1b77a638628eeef78a61123e51d61125e7f14141`／Build 52，没有改 App、构建或安装。
- 用户实际运行 23:33:09–23:37:19 的 summary 已核验：自动 UI 3/3、零失败／跳过，errors=[]，性能日志取回成功，前后无新增同名 crash。后台填写正常；横竖屏和返回重进填写“确认”，用户随后明确澄清“两项都正常”。三组短验收用户观察均正常，原 requiresReview 来自脚本输入误分类，不是已证实的 App 异常。
- 已修复脚本：明确 1 正常／2 异常选项；“确认”等文字要求澄清，不直接当故障或通过。空白／未知状态保留 pending，只有三项明确正常且无执行错误才记 userReportedNormal。新增回归后共 6/6 通过；不需要用户重新做本轮手机操作。
- 原 summary 保留，另存 `summary-reviewed.json` 和 `analysis.json` 补记澄清；原始 summary SHA-256 `ca1fbf369ea67b7af46c5b8ee0d6c60ad1891058c98b07d32b7cffaee94a2f1d`。详见 [一键验收分析](playback-build52-guided-acceptance-analysis-2026-11-02.md)。留存暂停边界报告 runID 未变，没有冒称是本轮新测量。设备数据仅本地归档。
- 性能线索：本轮期间更新的三条会话 totalFirstFrame 为 552／840／1450ms；后两条有网页回退取流，playURL 506／605ms，prepare 124／411ms。不同视频／编码／缓存，且每组仅一次，不认定整体性能改善或退化。
- 待办：保留 Build 52，下一阶段优先同条件首次加载采样，追踪取流回退与清单准备；耳机／系统中断仍待专项验收。原 main 改动保留，本轮 Mac 脚本和文档提交备份，不合并 PR、不启动云端回归。

## 2026-11-03 未点赞投币 401 调查轮

- 分支 `codex/coin-401-build53`，基线 `3461341a22fe44b060f46d30ed3cf148ed257c35`，原 main 未提交改动继续保留。初查时完整错误文字及同一视频先点赞后的结果尚待回复，随后用户已补充，见下轮记录。
- 已核对代码：未点赞 select_like=0，已点赞为 1，账号 Cookie／CSRF 来自互动用途快照，非幂等投币 POST 默认不自动重试。不能因 401 就擅自附加点赞、重试扣币或认定账号与点赞状态是根因。
- 已完成 Build 53 诊断增强：仅当投币接口业务码 -401 且返回明确人机验证决定时显示对应提示，其他服务端错误保持原样。仅解析 decisions，不记录验证凭据；没有改变请求参数／点赞、投币或重试行为。详情见 [投币调查](video-coin-401-investigation-2026-11-03.md)。
- 本地模拟回归：`coin401-repro.xcresult` 2/2、`coin401-verification.xcresult` 8/8 通过，验证明确验证信息、普通 -401、未点赞状态不变、不会自动重发、原表单及互动可靠性。模拟服务端不等于真实 401 已复现或功能修复。Build 53 全量单元 1230/1230、零失败／跳过；之后只将提示改为先核对投币状态，最终定向回归 8/8 通过。该阶段手机一度未连接，后续安装结果见下轮记录。
- 本地签名 Release 构建成功（125.5 秒），版本 1.1.1／Build 53 与签名深度核验通过；可执行文件 SHA-256 `8f0c4c418ae3b572ac7d4f2c7e55275d5aad552d917309e7327f1758668a2708`，构建记录 `build/logs/build53-device-build-info.json`。没有制作 IPA，既有 Swift 隔离警告仍在。构建完成时 RCe2027 离线，后续已连接并安装，见下轮记录。
- 当时待办：待设备连接后直接安装 Build 53；结合用户完整提示／先点赞结果继续定位。用户随后授权投币时自动点赞，具体实现及验收状态见下轮记录。

## 2026-11-03 投币时自动点赞／Build 54 轮

- 用户补充原提示为 `-401 非法访问`，同一视频先点赞后投币成功，并明确选择投币时自动点赞。先点赞同时改变账户状态与 select_like，不能仅据此断定服务端拒绝根因。
- Build 53 已在设备 RCe2027 上原位安装、启动 PID 74771，并核对版本 1.1.1（53）；实际构建的两个应用文件哈希与源码备份 `06719aab41ed82c56c2c4dbe862d848130b82f8e` 一致。Build 53 仅在响应明确包含验证要求时改进提示，未改变投币行为，其真机投币结果尚未采集。
- 本轮分支 `codex/coin-401-auto-like-build54`：投币 UI 明确显示同时点赞，投币请求统一 `select_like=1`，没有额外点赞 POST 或自动重投。仅服务端确认点赞后更新未点赞的本地状态，并保护已确认的状态不被旧刷新覆盖；服务端未确认时不虚报点赞。
- Build 54 本地针对性回归 10/10、全量单元 1232/1232 均通过，零失败／跳过。投币弹窗 UI 首轮因父级无障碍标识覆盖子按钮标识而未找到入口，按实际“投币”标签修正选择器后复跑 1/1 通过，确认提示与投币按钮可见可操作。证据 `build/logs/build54-coin-focused.*`、`build54-unit.*`、`build54-coin-ui.*`（首轮）、`build54-coin-ui-label.*`（复测）。
- 本地签名 Release 构建成功（279.0 秒），签名和 1.1.1／Build 54 核验通过；可执行文件 SHA-256 `00325a5cfacc4574ef6b76a376606a41faba38a9c2eb6a315c9af76531f22c8e`。设备原位安装、启动 PID 74985，设备应用列表确认 54；未卸载或清容器。构建记录 `build/logs/build54-device-build-info.json` 和设备记录 `build54-device-apps-after.json`，未制作 IPA，既有 Swift 隔离警告仍在。
- 下一步：用户选择一个未点赞、未投币的视频投一枚，确认是否成功及是否同时点赞；若仍为 -401，按是否提示验证继续收集信息。现有测试是模拟服务端或模拟器，真机尚未复测，不能提前认定 401 消失。没有自动向真实视频投币。原 main 未提交改动保留，不合并 PR、不主动发起云端完整回归。
- Build 54 源码及测试已备份：`fcb0fdaa7c59a17b3f3dddac8fbc6ccefe4e7122`，分支 `codex/coin-401-auto-like-build54`；本地与远端 tree 一致，设备实际构建的四个应用文件哈希与该提交逐一一致。构建时本地 HEAD 为 Build 53 的 `78adab7` 加未提交改动，没有冒称构建时已处于新提交。本记录随后单独做文档提交；用户真机投币结果仍待反馈。


## 2026-11-03 Build 55 评论排序控件

- 用户反馈 Build 54 投币已正常，确认为该场景的真机验收结果；不据此推断其他账号或服务端风控场景。
- 视频详情评论排序及初始加载占位改用 SwiftUI 系统分段 Picker，沿用动态评论的控件样式；切换仍通过既有排序加载流程。版本递增至 1.1.1 / Build 55。
- 使用 Xcode 27.1、指定 iPhone 18 Pro Max / iOS 27.0 模拟器及共享 DerivedData，针对性 UI 测试 1/1 通过，验证最热→最新→最热选择；结果 `build/logs/build55-comment-sort-ui.xcresult`。本轮未重跑全量测试或云端 CI。
- 本轮基线及分支：`codex/coin-401-auto-like-build54` / `e63f73bb7fc20a0719311457f359136cbc99e991`。Build 55 本地 Release 签名构建成功，签名和版本校验通过，原位安装并启动（PID 80290）；首次安装因会话残留旧设备编号失败，改用先前验收的设备后成功。评论排序真机体验待用户验收。源码及上述记录已备份到 `f28f34d961b5f98e6902fd9f17f91faec2051f88`；本句以独立文档提交补记。


## 2026-11-03 Build 56 自动恢复测试入口开关

- 开发者与诊断首页增加“显示自动恢复测试入口”开关，默认关闭并持久保存；开启时视频播放设置显示入口，关闭时隐藏。已有报告仍可在播放与网络诊断查看；使用说明同步更新。
- 模拟器（iPhone 18 Pro Max / iOS 27.0）相关回归 4/4 通过，涵盖隐藏、开启后测试页和报告复制；设置页开关、重启后持久化及菜单显示另 1/1 通过。持久化测试首次未进入“我的”（模拟器旧底栏设置影响），二次点击标签未改变系统开关，修正测试底栏及点击坐标后通过；结果分别位于 `build/logs/build56-recovery-ui.xcresult`、`build56-recovery-setting-ui*.xcresult`。未跑全量或云端 CI。
- 共享 Xcode-27 缓存的 Release 签名构建、签名校验及版本 56 校验通过；原位安装 iPhone 并启动，PID 80545，可执行文件 SHA-256 `6ceefe71a35c8fec19503d69566dd05792c3bcaf6e31b74810f2f207f6285b0b`。真机开关体验待验收；Build 55 评论排序真机体验也尚未收到反馈。
- 分支 `codex/coin-401-auto-like-build54`，本轮基线提交 `401f38a96a785c66bc3ab9dc1164e281f3188349`；本轮源码和记录已备份于 `1722f617a047b2053ccafd5f78a7d3cc44b1f736`；备份状态以独立文档提交补记。


## 2026-11-03 版本 1.1.2 / Build 57

- 对比 GitHub 最新正式 Release `v1.1.1`（tag 提交 `adf2995b61ad402f68d923407bd758f08a359bc6`）与当前分支，整理播放恢复与后台播放、收藏／稍后再看管理、评论草稿与显示、搜索和投币等用户可见变更。不能将未证实的整体播放性能改善写成已验证结果。
- 所有 Xcode 配置的 marketing version 升为 1.1.2，build 升为 57。共享缓存 Release 签名构建成功，版本与签名核验通过，原位安装 iPhone 并启动（PID 80682）。此轮仅变更版本元数据，未重跑测试或完整 CI，真机使用体验待验证；没有发布 GitHub Release。
- 分支 `codex/coin-401-auto-like-build54`；本地基线 `ed96771`，此前 Build 56 远端源码备份 `1722f617a047b2053ccafd5f78a7d3cc44b1f736`；因远端拉取连接超时，本地与远端相同文件树的提交 SHA 不同。本轮版本改动及记录已备份于 `dc96b587bedaa76f90d6fdc922f3e6422561cb6b`，备份状态以独立文档提交补记。


## 2026-11-03 1.1.2 Release 发布核对

- 本地使用共享缓存与既有脚本构建未签名 IPA，核验版本 1.1.2 / 57、bundle ID `cc.bili`、无签名目录及 embedded.mobileprovision；SHA-256 `c7a25b3558115e40929e50d4e9f658f2eb043953c278b37c750c76082eaaa58e`。
- GitHub Release 已发布中文说明并上传 IPA，页面显示的 SHA-256 与本地一致：https://github.com/Rone89/cilicili/releases/tag/v1.1.2 。未运行本轮完整云端回归。
- 发布页面选择了开发分支，但实际生成的 `v1.1.2` 标签指向旧基线 `adf2995b61ad402f68d923407bd758f08a359bc6`，因此 Release 自动生成的源码不对应 IPA；用户已同意修正到源码备份 `f15c51da490e5f1fda32b8574e5cfc8014f2e72d`；GitHub 网页不允许删除关联 Release 的标签，连接器更新标签报错，本机无 GitHub 推送凭据，标签尚未修正。Release 已明确警告并链接正确源码。不得误认源码一致。
- 本地分支 `codex/coin-401-auto-like-build54`，本轮基线 `36920f4`，本记录未提交。


## 2026-11-06 评论区 UIKit 重写 + gRPC 分页（Build 99–106）

- 评论量上千时 SwiftUI `LazyVStack` 滚动掉帧，用户选择"评论列表换 UIKit"。评论 tab 整页改为 `UITableView`（`VideoDetailCommentsUIKitPage` + `VideoDetailCommentsTableViewHost`），行内容仍复用 SwiftUI `CommentRow`，列表自身充当滚动容器（`contentInset.top = 播放器展开高度`，滚动收缩播放器、tab 位置恢复语义不变），分页由距底 320pt 阈值触发，失败态随滚动自动重试。LazyVStack 版评论列表保留给非交互外壳路径。
- 迭代过程中的已验证结论：`UICollectionViewCompositionalLayout` + 自适应行高会递归 invalidate 栈溢出；`UIHostingConfiguration` 换内容是异步的，自适配会量到"上一份内容"的高度（行重叠/空白/漂移三症状同源）；离屏预测高度不可靠（行内弹性视图随提议伸缩）。最终架构：自定义 cell 直持 `UIHostingController` 同步换 `rootView`，行高 = 显示捕获冻结值 → 离屏精确种子（提议 0）→ 兜底自适配。减速触摸即停由 `touchesBegan` 承担（手势识别器方案会抢 pan 导致不跟手，已废弃）。底部边缘评论页接入外壳绑定统一 .soft。详见 `docs/playback-empty-payload-rescue-analysis-2026-11-05.md` 追加一至七。
- "下滑加载失败频发"根因：网页版 `/x/v2/reply/main` 对短时连续翻页风控严格；PiliPlus 同场景走 gRPC `bilibili.main.community.reply.v1.Reply/MainList` 不受限流。项目听视频功能已有完整 gRPC 基建，评论分页复用（`BiliAPIClient+CommentsGrpc.swift`，字段号取自 PiliPlus proto，解码映射回现有 `CommentPage` JSON 结构，UI 零改动）；`fetchComments` 优先 gRPC、任意失败回退网页接口；失败退避 3/6/12s 指数、4 次后仅手动重试。gRPC 路径 DEBUG 且非 UI 测试夹具时生效（夹具拦截网页接口），Release 构建仍走网页路径，放开待真机稳定性确认。
- 测试：新增编解码单元测试 `BiliReplyMainListCodecTests`（假报文往返全字段断言）与 UI 用例（渲染滚动、自动翻页 60 条、参差行高往返稳定、触摸停止、行内点赞、排序、播放器收起耦合）全部通过；夹具评论改为参差行高并支持 3 页 × 20 条分页。全量单元/云端 CI 本轮未跑。
- 版本递增至 1.1.2 / Build 106，共享缓存 Release 签名构建、重签与无线安装 RCe2027 每轮完成并启动。真机验收：触摸停止/跟手、底部边缘统一、加载失败"明显减少"均由用户确认；行间稳定性在 104/105 曾反馈问题并于 106 前修复，最终行距稳定性待用户进一步确认。
- 本轮 99–106 累积改动已按整批提交：main `efff8fe`（19 文件，+2200/-56）；未推送远端、未合并 PR、未跑云端回归。
- 追加 Build 107：发现 106 的 gRPC 通道被 `#if DEBUG` 挡住而设备装的是 Release 包，真机"失败减少"实际来自 105 的退避。本版放开 gRPC 到 Release（仅 UI 测试夹具跳过）、失败先重试一次再回退网页、无 app 凭据时快速失败、每页写 `commentSource=grpc|web|grpcFailed` 诊断日志。单元与评论 UI 用例通过，Release 签名安装 RCe2027（安装成功，设备锁屏导致自动启动被拒，用户解锁后打开即可）。真机失败率待复测。

## 2026-11-06 评论页底色统一（Build 109）

- 反馈：评论区与简介页背景色不一致。模拟器（iPhone 18 Pro Max / iOS 27）同坐标像素采样：简介页内容区 `#F2F2F7`，评论页 `#FFFFFF`；深色模式两页均为 `#000000`，差异只在浅色模式可见。
- 根因：iOS 14+ `UITableViewCell` 的背景由 `backgroundConfiguration` 绘制，优先于 `backgroundColor`；`.plain` 表格默认配置是 `tableCellPlainBackgroundColor`（浅色纯白/深色纯黑）。UIKit 评论列表只把 `UITableView.backgroundColor` 设为 clear，cell 这层没清，表头/骨架/评论/footer 每一行都把整幅宽度刷白，盖住页面自己的分组灰底。运行时日志确认 cell 的 backgroundConfiguration 为该动态色，而 table、cell、contentView 均为 clear/nil。
- 修复：`VideoDetailCommentContentCell` 覆写 `init(style:reuseIdentifier:)`，清 `backgroundColor`、`contentView.backgroundColor`，并 `backgroundConfiguration = .clear()`。修复后同坐标评论页 = `#F2F2F7`。
- 回归：评论渲染滚动、自动翻页（60 条滑到“没有更多评论了”）两条 UI 用例通过；未跑全量单元或云端 CI。临时像素探针测试已删除，工作区只保留这一处产品改动。
- 版本 1.1.2 / Build 109；Release 未签名 IPA SHA-256 `d18c99757e80d4e78613b167ccadf48c5e87a87485aa80fc1f171d6a9ffa0873`，18pm 证书重签、签名深度校验通过，安装 RCe2027 成功（databaseSequenceNumber 2576）并启动。真机底色待用户确认。

## 2026-11-06 去掉首页推荐/热门切换动画（Build 110）

- 用户确认评论页底色已与简介页一致后，反馈首页“推荐 ↔ 热门”切换有动画。定位：`HomeFeedScrollContent` 对两种 mode 分别使用 `.transition(.move(edge: .leading/.trailing))`，外层 `.animation(.smooth(duration: 0.28), value: mode)`，旧列表向一侧滑出、新列表从另一侧滑入。该写法自 1.0.22（`932f0ed`，2026-09-01）就存在，后续 `10ec2ce` 仅补 Reduce Motion 判断，与本轮评论/背景改动无关。
- 按要求去掉切换动画：删除两处 `.transition` 与 `.animation(..., value: mode)`；保留按 mode 分叉的 identity，切换时整块内容直接替换。同时给 `HomeFeedScrollActions.requestScrollToTop` 增加 `animated` 参数，切换模式时瞬时回顶（`animated: false`），点首页 tab 回顶仍保留 0.34s 平滑滚动。
- 回归：`HomeRecommendationFeedbackUITests` 6/6 通过（点击、长按菜单、反馈、屏蔽、滚动不回顶）；未跑全量单元或云端 CI。动画是否彻底消失需真机确认（自动化难以断言“无动画”）。
- 版本 1.1.2 / Build 110；Release 未签名 IPA SHA-256 `8942f9c6b5550462994dd2b8a4762830b48d2474c479679176cb375e1a0fa100`，18pm 证书重签、签名深度校验通过，安装 RCe2027 成功（databaseSequenceNumber 2600）并启动。

## 2026-11-06 分P紧凑选择实验 / Build 111

- 用户新增实验开关需求：开启后视频详情页分P区改为单行显示当前分P名称与分P总数，点击以既有弹窗（"全部分P"玻璃网格）查看并选择；关闭时保持原横滑瓦片形态。`LibraryStore` 新增 `videoDetailCompactPageSelectorExperimentEnabled`（默认关闭、持久化，键 `cc.bili.videoDetail.compactPageSelectorExperimentEnabled.v1`），读取统一走 `boolValue` 以兼容启动参数域的字符串布尔；入口在"我的 → 开发者与诊断 → 实验开关"（`mine.experiments.compactPageSelector`），切换对已打开的详情页即时生效。
- 实现：`VideoDetailPageMenu` 按开关分叉为紧凑单行（含 P 号 + 分P标题 + 总数 + 展开三角，accessibilityLabel「分P，当前 Pn 标题，共 N P」）与经典形态；紧凑行复用既有 `VideoDetailPageSelectionSheet` 弹窗，`selectPage` 播放链路、云历史跨P恢复与听视频连播零改动。详情网络夹具新增 `--ui-test-video-multi-page`（三个分P），仅 DEBUG 生效。
- 测试：新增单元 `VideoDetailCompactPageSelectorTests` 2/2（持久化默认值与快照字段）；新增 UI `VideoDetailPageSelectorUITests` 3/3（经典形态回归、紧凑显示+弹窗选择 P2 后标签更新且弹窗关闭、单P隐藏），均在规定 iPhone 18 Pro Max / iOS 27.0 模拟器与共享 Xcode-27 缓存完成。两处调试结论已固化：shell 简介容器会把 `video.detail.summary` 标识符传播覆盖全部子元素，UI 测试对分P行/瓦片改用 `accessibilityLabel` 前缀查询；launch args 布尔是字符串，实验键必须走 `boolValue` 而非 `object as? Bool`。
- 签名环境注意：`~/.config/cilicili/sign-install-ipa.conf` 已被另一项目占用（Eric Kirsche 证书、旧设备 UDID，且 profile 路径已失效），本轮改用命令行直传 `--profile/--identity/--device`（18pm = Nazar Aryan G933USCY46，含 RCe2027，2027-09-22 到期）完成签名安装，未 `--save` 覆盖该配置；后续 cilicili 安装需继续直传或重做 cilicili 专用配置。
- 交付：版本 1.1.2 / Build 111；未签名 IPA SHA-256 `7d8bc55e3b44ece6aba353aead976905cf600909bfc4aaa365572a1fad75a09d`，签名深度校验通过，原位安装 RCe2027（databaseSequenceNumber 2624）并启动，可执行文件 SHA-256 `f9f16f6e7baafd499ca181da076055e88bb25bce40278fca31702fcdf1156600`。
- 待验收：用户真机确认紧凑行样式、弹窗手感、切P后播放/弹幕/续播正常。经典形态由 UI 回归保护，未跑全量单元与云端 CI。分支 main，本轮源码+文档为单次提交。

## 2026-11-06 分P弹窗重设计 / Build 112

- 用户要求：分P弹窗改单列一行一个P、左侧视频封面、右侧分P信息，左上角加收起按钮、右上角加正序/倒序切换按钮，图标不用主题色。实验开关与紧凑行入口保持 Build 111 行为；经典横滑形态的“展开全部分P”也打开同一新弹窗。
- 实现：`VideoDetailPageSelectionSheet` 整页重写为 `LazyVStack` 单列行（`VideoDetailPageSheetRow`：108×61 封面 = `AdaptiveVideoCoverImage` exactCrop + 右侧 P 号/part 标题/时长/当前播放），替换原玻璃两列网格；选中勾为灰色 `.secondary`；顶部 toolbar leading `chevron.down`「关闭」（`video.detail.pageSheet.close`），trailing `arrow.up/arrow.down`「正序/倒序」（`video.detail.pageSheet.order`），倒序仅反转展示顺序，不改变 P 号语义。旧 `VideoDetailPageSheetHeader/Route` 与 drag indicator 删除；经典横滑瓦片 `VideoDetailPageTile` 保留。
- 数据链路：`VideoDetailPlaybackRenderSnapshot` 新增 `coverDisplay: VideoCardDisplayModel?`，factory 由 `viewModel.detail` 构建，经 `VideoDetailPageSelectorRenderSnapshot/Store` 传入弹窗；封面为视频级（B站分P共用详情封面），非按P独立封面。
- 测试：夹具视频详情响应补 `pic` 字段。单元 2/2（新增 coverDisplay 断言）；UI 3/3 一次通过：紧凑用例覆盖关闭/排序按钮存在、倒序后 P3 在 P2 上方、恢复正序、选 P2 后行标签更新且弹窗自动收起；经典用例覆盖展开按钮打开新弹窗并可关闭；单P隐藏不变。证据 `build/logs/build112-pageselector-unit.xcresult`、`build112-pageselector-ui.xcresult`。未跑全量单元与云端 CI。
- 交付：版本 1.1.2 / Build 112；未签名 IPA SHA-256 `7af3bedc32da65690dd5d2c970a7399c8bbd176553bba702b58be31b3c522f48`；沿用直传 18pm 参数（不覆盖被其他项目占用的 conf）签名深度校验通过，原位安装 RCe2027（databaseSequenceNumber 2632）并启动；可执行文件 SHA-256 `6a01f754026a29a32e2869f2202f124f04d5ae682f0d8525c516a6e797ee7741`。
- 待验收：真机确认单列行视觉（封面加载、深浅色）、排序切换手感、关闭按钮位置。分支 main，本轮源码+文档单次提交。

## 2026-11-06 分P弹窗样式微调 / Build 113

- 用户真机反馈两点：顶部两个按钮图标仍是主题色；分P行不要背景容器。
- 修复：toolbar 按钮同时设 `.tint(.secondary)` 与图像 `.foregroundStyle(.secondary)`（主题 tint 会经 toolbar 桥接染色，单靠 foregroundStyle 不生效）；行改为无背景、无描边，行间用整宽 `Divider()`（spacing 0，行内 padding 8/8），列表恢复统一 14pt 水平内边距。选中勾与“当前播放”仍是灰色。
- 验证：改动仅 `VideoDetailPageMenu` 弹窗视图层；UI 回归 3/3 通过（`build/logs/build113-pageselector-ui.xcresult`），含排序与关闭断言；单元与夹具本轮无改动。未跑全量单元与云端 CI。
- 交付：1.1.2 / Build 113；未签名 IPA SHA-256 `b064b09a727b022f10bb2cd5ae09117258a7e449673c2fef39dc23d4ee89ddf1`；18pm 直传参数重签、深度校验通过，原位安装 RCe2027（databaseSequenceNumber 2640）并启动；可执行文件 SHA-256 `eb5bd0670b954e1127a5643267cf7567b40d28ea7a2abccf83e74a2fb0015753`。
- 待验收：真机确认顶部图标已非主题色、行间分割线样式。分支 main，本轮源码+文档单次提交。

## 2026-11-06 分集（番剧）接入紧凑选择 / Build 114

- 用户要求同一实验也接入番剧详情页的分集选择。实现：抽出共享组件 `VideoDetailCompactSelectionSheet.swift`——`VideoDetailCompactSelectionItem`（由 `VideoPage` 或 `PgcEpisode`+`PgcSeasonInfo` 映射）+ `VideoDetailCompactEntryButton`（区块名/当前项/总数单行）+ `VideoDetailCompactSelectionSheet`（单列封面行、分割线、灰色收起/排序按钮）。`VideoDetailPageMenu` 与 `VideoDetailPgcEpisodeSection` 均按开关分叉到共享组件，经典横滑形态各自原样保留；分集弹窗标题「全部分集」、计数单位「集」、标识 `video.detail.episodeMenu.compact`。
- 语义差异：UGC 分P封面是视频级（详情 pic）；PGC 每集有独立 `cover`,空则回季封面，仍无封面或无 CID 则置灰不可选（与旧瓦片一致）。旧分集 sheet 的两列玻璃网格与页眉胶囊排序按钮在实验开启时不再使用（关闭时保留原样）。
- 测试入口：`--start-bvid ep<id>` 现在解析为 `pgcEpisodeID` 种子，走 PGC 详情路径；夹具新增 `/pgc/view/web/season` 三集响应（每集独立封面，ep3 带"预告"角标）。
- 验证：单元 7/7（新增 page→item、episode→item、无 part 回落 Pn、无封面置灰回落季封面等 5 项）；UI 4/4 通过，新增 `testCompactEpisodeSelectorForPgcUsesSharedSheet`：分集紧凑行（"3 集"）、弹窗选「第2话」后行标签更新、经典展开按钮不出现。证据 `build/logs/build114-compact-selection-unit/.xcresult`、`build114-compact-selection-ui.xcresult`。未跑全量单元与云端 CI。
- 交付：1.1.2 / Build 114；未签名 IPA SHA-256 `adff9af96a62fcdd6da9cceb80f5a54e6a6993f2f0b6b55a61a86e2610f6ab5d`（构建完成后改过设置页文案，已删除旧 IPA 以最终源码重建，此为重建后校验值）；18pm 直传参数重签、深度校验通过，原位安装 RCe2027（databaseSequenceNumber 2648）并启动；可执行文件 SHA-256 `08fbdcd5b17ef86a9922ad9699307a809c5cbbadf7b3d050a336911dba9cbe67`。设置项文案同步改为"分P/分集紧凑选择实验"。
- 待验收：真机进入番剧详情确认分集紧凑行、每集独立封面、选集后播放切换正常。分支 main，本轮源码+文档单次提交。

## 2026-11-07 合集（ugc_season）接入紧凑选择 / Build 115

- 用户要求把视频播放页的合集也接入分P/分集实验。与分集轮的差异：详情接口 `/x/web-interface/view` 返回的 `ugc_season` 此前完全未解析、详情页没有任何合集区块，本轮需要先补数据链路再接共享组件。
- 模型：新增 `UgcSeason`/`UgcSeasonSection`/`UgcSeasonEpisode`（防御性解码，顶层字段缺失回落 `arc` 档案对象，毫秒时长归一）；`VideoItem` 增加 `ugcSeason`（CodingKeys `ugc_season`、init 带默认值、`mergingFilledValues` 以 fullDetail 优先）。
- 选择动作：新增 `selectUgcSeasonEpisode` 原地切换——合集条目是独立视频（不同 bvid），不能复用 `selectPage`（同视频换 cid）也不能直接用 `selectPgcEpisode`（有 `guard video.isPGCEpisode`）。守卫按纯 bvid 语义；切换时把 `ugcSeason` 带到新条目上（区块不消失），之后 `refreshDetailMetadata` 补拉 stat/UP主/简介（合集条目无完整档案，分集流程不需要这一步）。
- 视图：新增 `VideoDetailUgcSeasonSection`，数据同步来自 `detail.ugcSeason` 无额外请求，条目数 >1 才显示；实验开启=紧凑单行入口（`video.detail.seasonMenu.compact`，「合集」+「N 个」）+共享弹窗「全部合集」；关闭=横滑瓦片（`video.detail.seasonMenu`，展开按钮「展开全部合集」）。位置在 SummaryCard 与分P之间；选中匹配按 bvid。弹窗/弹窗行复用 Build 112/114 的共享组件零改动。
- fixture：`--ui-test-video-season` 独立开关（不影响既有用例），三集合集、每集独立封面、第 1 集即当前视频 `BV1xx411c7mD`。
- 测试：单元 12/12（新增 6 项：sections 展平解码、arc 回落与毫秒归一、紧凑条目映射含 `ugcSeason` 携带、缺 bvid 置灰、`mergingFilledValues` 合并、bvid 匹配），证据 `build/logs/build115-season-unit-5.xcresult`。UI 全组 `VideoDetailPageSelectorUITests` 6/6（新增紧凑合集弹窗选集原地切换、经典合集瓦片+展开弹窗+选集两用例），证据 `build/logs/build115-season-ui-final.xcresult`。未跑全量单元与云端 CI。
- 调试结论：本轮踩坑三处已修正——xcodebuild 少传 `test` 动作会静默变成纯 build（exit 0、0 用例，xcresult totalTestCount=0 识别）；经典瓦片 Button 的标签会被内层 tile 的 accessibilityLabel 合并成重复标签（`'合集视频 2, 合集视频 2'`），共享弹窗行是在 Button 层设 `.accessibilityLabel` 所以干净，经典瓦片同样把标签提到 Button 层修复；当前播放瓦片不是按钮，断言需用 `descendants(matching: .any)` 而非 `app.buttons`（与经典分P用例一致）。
- 交付：1.1.2 / Build 115（6 处配置全部递增）；未签名 IPA SHA-256 `cd2655a1178ec8a8b495a0e585bcc4710b20aa2e4dc07ef2f8de9128a89db478`；18pm 直传参数（不覆盖被其他项目占用的 conf）重签、深度校验通过，原位安装 RCe2027（databaseSequenceNumber 2656）并启动成功；重签后可执行文件 SHA-256 `eb61d3934fe39013d82d651f349e397f3c3d33ee98877cb5124454d1f151bc17`。
- 待验收：真机确认合集区块显示（实验开/关两种形态）、弹窗选集原地切换后播放/弹幕/续播正常、切换后 stat/UP主/简介等元数据正确回填。多 section 合集（如"正片/花絮"）按序展平不分组；听视频连播未接入合集语义，待后续需求。分支 main，本轮源码+文档单次提交。

## 2026-11-08 紧凑选择转正 + 删除 AI 字幕 / Build 116

- 用户要求：分P/分集实验转为正式默认功能，删除 AI 字幕实验。两个方向同时落地。
- 紧凑选择转正：删除 `videoDetailCompactPageSelectorExperimentEnabled`（属性/键/setter）及 Mine 页开关；`VideoDetailPageMenu`、`VideoDetailPgcEpisodeSection`、`VideoDetailUgcSeasonSection` 三个区块移除实验分叉，仅保留紧凑形态（单行入口 + 共享单列弹窗）。经典横滑瓦片、PGC 旧玻璃网格弹窗、`VideoDetailPgcEpisodeOrder` 等死代码整体删除；`InitialPageMenuPlaceholder` 占位改为紧凑行骨架形态。旧 UserDefaults 键在 init 退役键清理区移除（init 兜底）。
- AI 字幕整体删除：`VideoDetailSubtitleActions/Store/PlayerSurfaceSubtitleLayer`、`BiliAPIClient+VideoSubtitles`、`docs/ai-subtitle-experiment.md` 删除；`aiSubtitleExperimentEnabled` 开关及 Mine 页入口移除；弹幕设置面板的 `VideoDetailSubtitleSection` 与 `subtitleStore/onSelectSubtitleTrack` 参数链（Sheet/Host/Content/ShellSurfaceHost/夹具）清理；`SubtitleDanmakuResourceCache` 剥离字幕半区并更名 `DanmakuResourceCache`（`TimedResourceCacheStatistics.subtitleCount` 删除），缓存诊断/清理 UI 行改为"弹幕"。历史分析文档中的 AI 字幕提及保留为历史记录。
- 测试：单元 43/43（`VideoDetailCompactPageSelectorTests` 删实验持久化用例；`ResourceLoadingServicesTests` 缓存用例重写为纯弹幕键隔离；`BiliAPIClientRequestContractTests` 缓存类型名同步），证据 `build/logs/build116-graduate-unit-2.xcresult`。UI 6/6：选择器组删两个经典形态用例、全部 launch args 去实验开关参数（`VideoDetailPageSelectorUITests` 整体重写为 4 用例），另回归弹幕设置面板两项，证据 `build/logs/build116-graduate-ui.xcresult`。未跑全量单元与云端 CI。
- 交付：1.1.2 / Build 116（6 处配置递增）；未签名 IPA SHA-256 `1e96b8985f93cb6f400bff694f07700cb2330dc827bce93ff4bd574739a10f6d`；18pm 直传参数重签、深度校验通过，原位安装 RCe2027（databaseSequenceNumber 2664）并启动；重签后可执行文件 SHA-256 `966c7704f01bc4e7500173d0d1c9021ded53b29eac095d652ae12d036c2e0ec0`。
- 待验收：真机确认无实验开关时分P/分集/合集紧凑形态直接可用；弹幕设置面板不再出现字幕区；资源缓存诊断行显示"弹幕"（原"字幕/弹幕"）。分支 main，本轮源码+文档单次提交。

## 2026-11-08 AI 字幕重建为正式功能 / Build 117（分支 zcode/ai-subtitles）

- 背景：Build 116 应用户要求退役了实验版 AI 字幕；用户随后要求参考 PiliPlus 重建为正式功能，UI 入口选定为控制条 CC 按钮。在独立工作树 `~/.zcode/worktrees/ai-subtitles`（分支 `zcode/ai-subtitles`，基于 build 116 提交 `534550a`）开发。
- 管线重建（参考 PiliPlus 与 build 68 旧实现）：`BiliAPIClient+VideoSubtitles` 走 `/x/player/wbi/v2`（WBI 签名 + 登录 cookie）拉字幕轨（`type==1` 为 AI 轨），下载 cue JSON（优先 `subtitle_url_v2`，http 升 https）；`VideoDetailSubtitleStore` 持轨列表/选中轨/按 lan 的 cue 缓存/二分定位当前 cue；`VideoDetailSubtitleActions` 接到 `VideoDetailViewModel`（`subtitleRenderStore` 重新挂回 RenderStores）。
- 选轨偏好：新增 `VideoSubtitlePreference` 四档（关闭=默认 / 优先真人 / 仅真人 / 静音时自动开 AI），`LibraryStore` 持久化键 `cc.bili.playback.videoSubtitlePreference.v1`；轨排序对齐 PiliPlus（中文优先、同语言真人先于 AI）。AI 判定、静音判定（`isMuted || volume<=0`）与 PiliPlus 语义一致。
- UI：控制条新增字幕（CC）按钮（仅字幕轨存在时显示，经 `controlsAccessory` 槽位注入，全屏状态与更多播放设置按钮共存），点开选轨弹层（关闭 + 各轨 `lan_doc`，AI 轨带「AI」角标）；竖屏播放设置与横屏播放设置面板各加「字幕」行进入共享的 `SurfaceOnlySubtitleSettingsPage` 偏好页；底部胶囊渲染层复用 `PlayerPlaybackClock` 0.2s 节流驱动，zIndex 2.55（弹幕 2.5 与控制条 3 之间），转场/听书模式自动收起弹层。
- 测试：新增 `VideoDetailSubtitleStoreTests` 8/8 通过（排序、四档偏好×三种轨组合、cue 二分边界、按 lan 缓存隔离），证据 `/tmp/ccswift-subtitle-tests3.xcresult`。全量单元 1256 项：1249 通过、7 失败——3 项评论分页（DynamicDetailNavigation×2 + MainComments×1）经 stash 基线实验确认在**未含本轮改动的 pristine build 116 上同样失败**（build 116 遗留，非本轮引入）；其余 4 项未做基线复核，其中 2 项为 DeterministicAVPlayerTransport 的 writer 超时（历史上即主机环境敏感）、1 项启动竞态（历史记录同为环境依赖）、1 项同评论分页组。本轮未修改这些模块。
- 交付：1.1.2 / Build 117（6 处配置递增）；未签名 IPA SHA-256 `3dec436665dd7ee0381141d4d7148d3520f46470f0951d4fbb9f46c161bb11a7`；18pm 直传参数重签安装 RCe2027（结果见下轮补记）。
- 待验收：真机播放有 AI 字幕的视频，确认控制条出现 CC 按钮、弹层选轨即时生效、AI 角标正确；播放设置→字幕四档偏好切换后重进视频生效；无字幕轨视频不显示 CC 按钮。评论分页 3 项失败为 build 116 遗留，待单独排查。分支 `zcode/ai-subtitles`，本轮源码+文档提交 `768548d` + 文档提交。

## 2026-11-08 Build 117 真机反馈修复：CC 按钮无响应 / Build 118

- 用户实测 Build 117 真机点击字幕按钮无反应，并给出参考视频 `BV1hA4a6yEp9`（PiliPlus 下有多条 AI 字幕轨）。排查确认 B 站 `/x/player/v2` 匿名请求字幕列表为空，AI 字幕需要登录态；App 侧管线（拉轨→解码 cue→渲染）在模拟器带夹具时可完整走通，因此问题在 UI 交互层。
- 根因一：控制条 CC 按钮用「玻璃修饰的 SwiftUI Button」，在 `UIHostingController` 嵌 UIKit 的播放器 overlay 里吞掉点击。项目里 `SurfaceOnlyUIKitMoreControlsButton` 的注释已记录同一个坑（"The owning SwiftUI view supplies the glass; UIKit only owns touch delivery"）。修复：CC 按钮改为 `UIViewRepresentable` + `UIButton(primaryAction:)` 承担触摸，SwiftUI 只提供玻璃外观（`biliPlayerClearGlass`）。
- 根因二：选轨用系统 `.sheet`，在同一宿主结构下弹不出来（弹幕设置/更多播放设置都走 UIKit 回调在 overlay 外呈现，未用系统 sheet）。修复：改为 overlay 内浮层 `VideoDetailSubtitleSelectionPanel`（对齐横屏 `SurfaceOnlyLandscapeMoreControlsOverlay` 的既有模式），含 AI 角标、选中勾、点背景关闭。
- 顺带修复：暂停时播放时钟不发 tick，选轨后 cue 不显示。`selectSubtitleTrack` 结束时按 `playbackClock.currentTime` 立即求值一次 cue。
- 诊断设施（保留）：`--subtitle-fixture` DEBUG 启动参数注入两条假轨（真人/AI）与覆盖 0-600s 的 cue，无需登录即可端到端验证 UI 链路；同时豁免控制条 3 秒自动隐藏（`PlayerPlaybackControlsVisibilityModel`，DEBUG only）。新增 `VideoDetailSubtitleActions` 内的 Subtitle OSLog 分类（`cc.bili/Subtitle`）。
- 测试：`VideoDetailSubtitleUITests` 首次执行 2/2 通过——CC 按钮命中 → 浮层出现 → 选 AI 轨 → 底部渲染「AI 夹具句」；选真人轨 → 渲染「字幕夹具第一句」。检查日志确认 `cc button tapped` → `panel rendering tracks=2` → `select lan=ai-zh` 全链路探针命中。后续多轮复跑出现不稳定：定位为**并行会话（另一 xcodebuild 进程）抢占同一台 iPhone 18 Pro Max 模拟器**，App 被互相 terminate 导致按钮查不到，与代码无关；日志中 `xcrun simctl` 截图亦超时，设备列表显示多台 unavailable。
- 单元：`VideoDetailSubtitleStoreTests` 8/8 通过保持。
- 交付：1.1.2 / Build 118（6 处配置递增）；未签名 IPA SHA-256 `1aff1e705220125a7692d5f6463c19bb470ba41778652d46cbba13ee4c15cb76`；18pm 重签校验通过（`satisfies its Designated Requirement`），**无线安装失败**：`CoreDeviceError 4016`，设备 `00008160-001C311028434036` 与其他设备同为 `unavailable`，待设备解锁/唤醒、无线调试恢复后重装。
- 待验收：真机播放 `BV1hA4a6yEp9`（或其他有字幕的视频）确认 ① 控制条出现 CC 图标 ② 点按弹出选轨浮层 ③ 选中轨后底部出现字幕 ④ 暂停时选轨也能立即显示 ⑤ 设置→字幕四档偏好生效。分支 `zcode/ai-subtitles`，提交 `768548d`（功能）、`24f54db`（117 文档）、`5638b18`（本次修复）。

## 2026-11-08 真机反馈四项修复 / Build 119

- 用户提供真机截图反馈四项：① 字幕按钮无图标 ② 选轨弹窗不是 iOS 原生弹窗 ③ 弹窗超出画面 ④ 选完字幕不显示内容。截图同时证明**字幕轨已成功获取**（弹窗中出现「العربية AI」「Português AI」等 AI 轨），问题在呈现层与 cue 下载。
- ① 图标：原实现用子视图 tag + `UIImage(systemName:)`，图标未渲染。改为 `UIButton.Configuration.image`，符号换为 `captions.bubble` / `captions.bubble.fill`（选中态实心）。
- ② 原生弹窗 + ③ 溢出：自绘 overlay 浮层整体移除，改为 `UIAlertController(actionSheet)` 由 UIKit 直接呈现（`topMostViewController` + iPad/横屏 popover 锚点）。此前尝试的 SwiftUI `.sheet` 经 UI 测试元素树确认在该 UIKit 宿主 overlay 内不会弹出，故不可用。系统 action sheet 自带布局、滚动、安全区处理，溢出问题随之消失。
- ④ 选完不显示：`fetchVideoSubtitleCues` 此前只带 `Accept: application/json`，字幕 CDN（aisubtitle.hdslb.com 等）会拒绝。改为复用 `BiliURLSessionFactory.apiHeaders(referer:userAgent:cookieHeader:)` 补齐 UA/Referer/登录 cookie，与播放详情请求一致。另保留暂停时选轨立即求值 cue 的修复。
- 测试：`VideoDetailSubtitleUITests` 两条用例在交替运行中**各自通过**——选 AI 轨渲染「AI 夹具句」、选真人轨渲染「字幕夹具第一句」，覆盖按钮命中 → 原生 action sheet → 选轨 → 底部渲染全链路。两条同时稳定通过受并行会话抢模拟器影响（App 被互相 terminate），已记录为环境限制而非代码缺陷。
- 交付：1.1.2 / Build 119（6 处配置递增）；未签名 IPA SHA-256 `02c37dc5330fca0ae954e0a3e5491b1a7a18d9192af8f38a57117166fe88d0a7`；重签通过（Designated Requirement satisfied），**无线安装仍失败**：`CoreDeviceError 4016`，RCe2027 与其他设备均 `unavailable`，待设备解锁并恢复无线调试后重装。
- 待验收：真机播放 `BV1hA4a6yEp9`，确认 ① CC 图标可见（空心/实心随选中态）② 点按弹出系统 action sheet ③ 弹窗不溢出画面 ④ 选 AI 轨后底部出现字幕文本。

## 2026-11-08 「开启字幕后仍无字幕」修复 / Build 120

- 用户确认 Build 119 的图标、原生弹窗、布局三项均已正常，仅剩「选完字幕不显示内容」。字幕轨列表能列出（含多条 AI 语言），说明 `/x/player/wbi/v2` 与选轨 UI 正常，问题在 cue 下载。
- 根因：接口下发的字幕地址是**协议相对地址**（`//aisubtitle.hdslb.com/bfs/ai_subtitle/prod/xxx.json`）。原实现只把 `http://` 升级为 `https://`，`//` 前缀交给 `URL(string:)` 会得到无 scheme 地址，请求直接失败；且错误只写入 store，界面上没有任何反馈。PiliPlus 的 `Request().get("https:$subtitleUrl")` 正是为此始终补 `https:` 前缀。
- 修复：新增 `BiliAPIClient.normalizedSubtitleURL(_:)`——`//` 补 `https:`、`http://` 升级、裸域名补 `https://`、去首尾空白。`selectSubtitleTrack` 改为先试 `subtitle_url_v2`、失败或为空回落 `subtitle_url`；每次选轨先清空旧错误；日志记录 host 与 cue 数量，便于真机诊断。
- 可见性：字幕层在「无 cue 且有错误」时显示一行提示（如「字幕内容加载失败」「该字幕轨内容为空」），不再出现「选了却毫无反应」。
- 测试：`VideoDetailSubtitleStoreTests` 11/11 通过（新增 3 项 URL 规范化：协议相对、http 升级、裸域名+空白），证据 `/tmp/ccswift-subtitle-urlfix.xcresult`。
- 交付：1.1.2 / Build 120；未签名 IPA SHA-256 `6b5eacb8d1d7e60d4ebcceff024a106cb6b4271c9abe789d488a76abeff36e1a`；重签未执行——RCe2027 持续 `unavailable`（无线调试断开），待设备在线后安装。
- 待验收：真机播放 `BV1hA4a6yEp9` 选任意 AI 轨，确认底部出现字幕文本；若出现「字幕内容加载失败」提示，按 `cc.bili/Subtitle` 日志中的 host 与错误码继续定位。

- 补记：设备恢复在线（`available (paired)`）后执行重签安装成功——`app.bamboo2779.brussels691` 1.1.2 / Build 120，databaseSequenceNumber 2704，已启动。设备上同时存在旧包 `cc.bili` 1.1.2 / Build 119（非本轮 18pm 重签目标），验收时须打开「cilicili」且版本为 120 的那个（bundle ID `app.bamboo2779.brussels691`）。

## 2026-11-08 字幕位置/样式对齐 PiliPlus 默认值 / Build 121

- 用户询问字幕位置是否与 PiliPlus 一致，并要求「只对齐默认值与避让」，不新增设置面板。
- 对照 PiliPlus 实现（`lib/plugin/pl_player/controller.dart` 的 `getSubConfig` 与 `lib/utils/storage_pref.dart` 默认值）：`subtitlePaddingH=24`、`subtitlePaddingB=24`、`subtitleBgOpacity=0.67`、`subtitleFontScale=1.0`、`subtitleFontScaleFS=1.5`、字号 16×缩放；`view.dart` 中控制条可见且字幕开启时把 `subtitlePaddingB` 临时抬到 `minPadding=70`，隐藏后恢复。
- 本工程改动（`VideoDetailPlayerSurfaceSubtitleLayer.swift` + Shell 调用点）：底部/水平 24pt；控制条可见时底部 `max(24, 70)` 并带 0.2s 缓动；字号 `16 ×（全屏 1.5 / 竖屏 1.0）`；背景不透明度 0.67；新增 `controlsVisibility`、`isFullscreen` 输入。错误提示沿用同一底部避让。
- 明确未实现（PiliPlus 有、本轮按用户选择不做）：字幕设置面板（字号/透明度/间距/字重/描边滑块）、字幕拖动定位与持久化。
- 交付：1.1.2 / Build 121；未签名 IPA SHA-256 `2037aec97305562fa10278653cc85d6fa26644165af99ea52d2585f6769db984`；18pm 重签通过并安装 RCe2027（databaseSequenceNumber 2712）后启动成功。
- 待验收：竖屏控制条出现时字幕上移且不被遮挡；横屏/全屏字幕明显放大；背景比 Build 120 更实一些。

## 2026-11-08 更正：选轨偏好严格对齐 PiliPlus / Build 122

- 用户询问 PiliPlus 是否有「优先真人/仅真人」设置，核对后发现上一轮表述有误：PiliPlus 的 `SubtitlePrefType` 四档为 `off` / `on`（优先选择非自动生成AI字幕，取排序后第一条）/ `withoutAi`（跳过AI：首选轨是 AI 就关闭，否则取第一条）/ `auto`（静音等同 `on`，非静音等同 `withoutAi`），**没有「仅真人字幕」这一档**。原实现的 `humanOnly` 属自加语义（会退而选任意非 AI 轨，如英文 CC），与 PiliPlus「宁可关闭」不同。
- 按用户要求严格对齐：`VideoSubtitlePreference` 改为 `off / preferNonAI / withoutAI / autoWhenMuted`，选轨一律取排序后第一条（中文优先、同语言真人先于 AI，与 PiliPlus `SubtitleInfo` 排序一致）；设置页文案改为 PiliPlus 口径（优先非AI字幕 / 跳过AI字幕 / 静音时自动）。
- 测试：`VideoDetailSubtitleStoreTests` 11/11 通过，新增边界用例「中文AI + 英文真人CC」——`preferNonAI` 取中文 AI（zh 优先）、`withoutAI` 返回 nil（首选是 AI 即关闭），与 PiliPlus 行为一致。
- 交付：1.1.2 / Build 122；未签名 IPA SHA-256 `d8f830631ea2e71cea22bf6db11af1ae5734be1a14111eb5fad950e6f71f8f8d`；18pm 重签安装 RCe2027（databaseSequenceNumber 2728）并启动。
- 待验收：设置→字幕中四档名称与新语义（尤其「跳过AI字幕」在只有 AI 轨时应不显示字幕）。
