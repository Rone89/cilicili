# 未点赞视频投币出现 401：调查与诊断增强

## 当前结论

用户反馈未点赞时投币显示 401。尚未取得本次完整提示、HTTP 状态与业务码，也未验证同一视频先点赞后是否成功，因此根因尚未确认；不能把本轮的模拟响应说成真实服务端复现，也不能认定问题已修复。

客户端路径：`VideoDetailViewModel.addCoin` 根据当前点赞状态传入 `selectLike`，未点赞发送 `select_like=0`，已点赞发送 `1`；两者都会提交 interaction purpose 账号的 Cookie 和 CSRF。当前投币界面没有“同时点赞”选项。`select_like` 语义为投币时附加点赞，不能无证据地将 0 改成 1：那会改变用户点赞状态。代码单独给 POST 使用默认不可重试策略，避免多次扣币。

外部有其他请求的 [实际 -401 风控验证响应记录](https://github.com/RayWangQvQ/BiliBiliToolPro/issues/346)，HTTP 200 的 JSON 包含 `ga_data.decisions`；这不是本用户的投币响应，不能据此外推本次一定触发验证。也不能将业务码 -401 和 HTTP 401 混为一谈。

## 本轮改动和验证

Build 53 诊断增强只在投币接口业务码为 -401 且明确带 `verify_captcha_level2` 时，提示“B站要求安全验证，请在官方页面验证并确认投币状态”；没有该证据时保留原始服务端错误。只读取 decisions，未记录、导出或保存凭据和其他验证字段，不自动投币、点赞、重试或绕过验证。

本地模拟 `-401 + ga_data`：未点赞时请求 select_like=0，收到拒绝后保持原有点赞和投币状态、没有第二次 POST，显示安全验证提示；无验证字段的 -401 保留原始错误。既有 select_like=1 表单、互动可靠性测试也通过。模拟后端只能验证客户端处理，不能证明服务端会接受任一请求；真实账号、视频与 B 站响应需真机验证。

当前账号报错的详细文字和先点赞后结果仍待用户提供。若真实提示为 HTTP 401、无验证字段的 -401 或其他值，按实际响应继续定位，不修改隐私、设备指纹或点赞行为来猜测通过。

## 环境与取证

工作树 `/Users/rayc/Desktop/cilicili-build48`，分支 `codex/coin-401-build53`，基线 `3461341a22fe44b060f46d30ed3cf148ed257c35`。原始和最终定向测试分别在 `build/logs/coin401-repro.*` 与 `coin401-verification.*`；全量单元和本地 Release／设备结果见 DEVELOPMENT_STATUS.md。保留用户原 main 改动，不合并 PR。测试中没有对真实视频发投币请求。
