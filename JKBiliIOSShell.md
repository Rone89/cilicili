# JKBili iOS 开发入口

我已经按第一版 MVP 方向准备了一套 SwiftUI 源码骨架，放在：

`D:\workspace\newbili\JKBiliiOS`

建议在 macOS 上新建一个 iOS App 工程，然后把 `JKBiliiOS\Sources` 下的文件按目录拖进 Xcode。第一版目标是：能登录、能刷推荐、能搜索、能看视频、能看评论和弹幕。

## 当前产物

- `JKBiliiOS\README.md`：工程导入和运行说明
- `JKBiliiOS\Docs\MVP_Roadmap.md`：功能路线和迭代顺序
- `JKBiliiOS\Docs\API_Mapping.md`：iOS 模块和 Bilibili 接口映射
- `JKBiliiOS\Sources`：SwiftUI + URLSession + AVPlayer 的源码骨架

## 重要边界

这个项目只规划和实现用户正常可访问内容的客户端能力，不做会员/版权/风控限制绕过，不做账号滥用，不做自动化刷量或批量操作。

