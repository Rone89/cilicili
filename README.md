# cilicili

cilicili 是一个使用 SwiftUI 开发的第三方 iOS 客户端实验项目，重点探索更轻量的 B 站浏览、动态、视频播放和弹幕体验。

> 本项目仅用于学习、研究和个人使用。项目不隶属于哔哩哔哩，也不包含任何账号凭据、签名证书或私有接口密钥。请遵守目标平台服务条款和当地法律法规。

官方 Telegram 频道：[@cilicili89](https://t.me/cilicili89)

## 功能概览

- 首页推荐、搜索、UP 主空间、视频详情和相关推荐。
- 动态页支持图文、视频动态、转发动态展示。
- 视频详情页包含评论、弹幕、点赞、投币、收藏、分享等交互入口。
- 基于 AVPlayer 的 HLS Bridge 播放链路，面向 iOS 26+ 设备优化 HEVC 硬件解码体验。
- 支持弹幕开关、弹幕样式设置、内容关键词过滤、图片大图预览和组图切换。
- 支持二维码登录和 Web 登录，登录态存储在本机 Keychain 中。
- GitHub Actions 可自动构建 Release 未签名 IPA。

## 环境要求

- macOS + Xcode 26.5 或更新版本。
- iOS 26.1+。
- Swift 6 工具链、Swift 5 language mode / SwiftUI。工程已启用 Approachable Concurrency 和默认 MainActor 隔离，并会逐步迁移到完整 Swift 6 language mode。
- 目标设备建议 iPhone 16 及以上机型。

## 本地运行

```bash
xcodebuild \
  -project bili.xcodeproj \
  -scheme bili \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone Air' \
  build
```

也可以直接用 Xcode 打开 `bili.xcodeproj`，选择 `bili` scheme 后运行。

## 构建未签名 IPA

未签名 IPA 适合上传到 GitHub Release 或交给其他签名工具继续处理，不能直接作为 App Store/TestFlight 包发布。

```bash
zsh Scripts/build-release-unsigned-ipa.sh
```

## GitHub Actions

仓库内置两类自动化：

- Pull Request 和主分支推送会执行模拟器编译、单元测试、覆盖率摘要和增量格式检查。
- `.github/workflows/unsigned-ipa.yml` 只在版本 Tag 或手动触发时构建 Release 未签名 IPA，普通提交不再重复打包。

## 本地签名配置

仓库不保存个人 Team ID、发布 Bundle ID、Provisioning Profile 或证书路径。本地真机和发布签名通过以下忽略文件配置：

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
cp Config/Signing.local.env.example Config/Signing.local.env
```

`Signing.local.xcconfig` 供 Xcode Release 配置使用，`Signing.local.env` 供签名和真机安装脚本读取。未签名 IPA 构建不需要这些文件。

## 隐私与安全

- 仓库不提交 `.ipa`、`.dSYM`、签名证书、Provisioning Profile、`.env` 或本地配置文件。
- 登录态仅保存在本机 Keychain，不应提交到 Git。
- 如果 fork 或二次开发，请自行检查是否引入了个人账号、token、证书或本地路径。

## 致谢

感谢以下开源项目与社区实现带来的启发和支持：

- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)
- [MiniBili](https://github.com/ResistanceTo/MiniBili-WEB)
- [PiliPod](https://github.com/BPTPW/PiliPod)

## 许可证

本项目采用 [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html)（GPL-3.0-only）开源。你可以在遵守协议的前提下学习、复制、修改和分发本项目代码；分发修改版本或基于本项目的作品时，需要保留版权与许可声明，并以同一协议开放对应源代码。

发布源码或二进制产物时，请按 GPLv3 要求一并提供对应源代码、许可文本和必要的构建说明。

本项目引用或参考的第三方项目保留各自版权与许可，使用时请同时遵循对应项目的开源协议和服务条款。

## Support / 支持

CiliCili 的源码可以免费阅读、使用和改造，但开发、调试和持续维护用掉的 AI Token 并不会自己续费。如果这个项目确实帮到了你，欢迎通过 Star、反馈、分享，或自愿赞助来支持它继续慢慢变好；不赞助也完全没关系，每一种支持都很珍贵。

Support is always optional. If CiliCili saves you a little time or makes watching videos more comfortable, a Star, an Issue, a share, or a small contribution all help keep the project moving.

[查看支持方式与支付宝二维码](SUPPORT.md)
