# cilicili

cilicili 是一个使用 SwiftUI 开发的第三方 iOS 客户端实验项目，重点探索更轻量的 B 站浏览、动态、视频播放和弹幕体验。

> 本项目仅用于学习、研究和个人使用。项目不隶属于哔哩哔哩，也不包含任何账号凭据、签名证书或私有接口密钥。请遵守目标平台服务条款和当地法律法规。

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
- iOS 26.4+。
- Swift 6 / SwiftUI。
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
DERIVED_DATA_PATH="$PWD/build/UnsignedIPADerivedData"
BUILD_DIR="$PWD/build/ipa"

rm -rf "$DERIVED_DATA_PATH" "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Payload"

xcodebuild \
  -project bili.xcodeproj \
  -scheme bili \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  COPY_PHASE_STRIP=YES \
  STRIP_INSTALLED_PRODUCT=YES \
  DEPLOYMENT_POSTPROCESSING=YES \
  build

APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products" -maxdepth 2 -name '*.app' -type d | head -n 1)"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
(cd "$BUILD_DIR" && zip -qry cilicili-release-unsigned.ipa Payload)
```

## GitHub Actions

仓库内置 `.github/workflows/unsigned-ipa.yml`，每次推送到 `main` 或手动触发 workflow 时，会构建一个 Release 未签名 IPA artifact。

## 隐私与安全

- 仓库不提交 `.ipa`、`.dSYM`、签名证书、Provisioning Profile、`.env` 或本地配置文件。
- 登录态仅保存在本机 Keychain，不应提交到 Git。
- 如果 fork 或二次开发，请自行检查是否引入了个人账号、token、证书或本地路径。

## 许可证

当前仓库尚未声明开源许可证。默认情况下，未经作者许可不授予复制、分发或商用权利。
