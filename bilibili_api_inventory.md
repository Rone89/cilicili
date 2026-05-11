# JKVideo 项目 Bilibili 接口整理

来源项目：[tiajinsha/JKVideo](https://github.com/tiajinsha/JKVideo)  
本地源码目录：`D:\workspace\newbili\_jkvideo_source`  
扫描提交：`4706845f440913be6f85409d190f92acd5fd9bbe`  
整理日期：2026-05-01  

## 说明

这份文档基于源码静态扫描整理，重点文件是 `services/bilibili.ts`、`dev-proxy.js`、`utils/wbi.ts`、`utils/imageUrl.ts`。未实际调用 B 站接口验证返回值。

Web 端会通过本地代理访问 B 站，Native 端直接请求真实域名。项目里常用请求头包括：

- `Referer: https://www.bilibili.com`
- `Origin: https://www.bilibili.com`
- `User-Agent: Mozilla/5.0 ... Chrome/120 ...`
- `Cookie: buvid3=...; SESSDATA=...`

项目会本地生成并保存 `buvid3`，登录后保存 `SESSDATA`。部分接口使用 WBI 签名，签名参数来自 `/x/web-interface/nav` 返回的 `wbi_img`，再由 `utils/wbi.ts` 生成 `wts` 和 `w_rid`。

## 基础域名与代理

| 用途 | Native 真实地址 | Web 本地代理 | 源码位置 |
|---|---|---|---|
| 主站 API | `https://api.bilibili.com` | `http://localhost:3001/bilibili-api` | `services/bilibili.ts:12`, `dev-proxy.js:60` |
| 登录 API | `https://passport.bilibili.com` | `http://localhost:3001/bilibili-passport` | `services/bilibili.ts:13`, `dev-proxy.js:61` |
| 直播 API | `https://api.live.bilibili.com` | `http://localhost:3001/bilibili-live` | `services/bilibili.ts:298`, `dev-proxy.js:62` |
| 弹幕 XML | `https://comment.bilibili.com` | `http://localhost:3001/bilibili-comment` | `services/bilibili.ts:14-16`, `dev-proxy.js:65` |
| 图片 CDN | `*.hdslb.com` | `http://localhost:3001/bilibili-img/{host}/...` | `utils/imageUrl.ts:7-13`, `dev-proxy.js:100` |
| 直播弹幕 WebSocket 代理 | 上游由 `host` 参数指定，要求包含 `bilibili.com` | `ws://<LAN-IP>:3001/bilibili-danmaku-ws?host=...` | `dev-proxy.js:113-123` |

备注：源码里实现了 WebSocket 代理能力，但业务代码当前主要用直播历史弹幕轮询接口，未发现直接构造直播弹幕 WebSocket 上游地址的调用。

## 接口清单

| 功能 | 方法 | 地址 | 主要参数 | 登录/签名 | 源码位置 |
|---|---|---|---|---|---|
| 获取 WBI key、用户导航信息 | GET | `https://api.bilibili.com/x/web-interface/nav` | 无 | 可带 `SESSDATA`；用于提取 `wbi_img` | `services/bilibili.ts:87-90`, `224-226` |
| 首页推荐视频流 | GET | `https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd` | `fresh_type=3`, `fresh_idx`, `fresh_idx_1h`, `ps=21`, `feed_version=V8`, `wts`, `w_rid` | WBI 签名 | `services/bilibili.ts:106-113` |
| 热门视频 | GET | `https://api.bilibili.com/x/web-interface/popular` | `pn`, `ps=20` | 未签名；当前封装后未发现 UI 调用 | `services/bilibili.ts:125-127` |
| 视频详情 | GET | `https://api.bilibili.com/x/web-interface/view` | `bvid` | 可带 Cookie | `services/bilibili.ts:130-133` |
| 相关推荐 | GET | `https://api.bilibili.com/x/web-interface/archive/related` | `bvid` | 可带 Cookie | `services/bilibili.ts:137-139` |
| 视频播放地址 | GET | `https://api.bilibili.com/x/player/playurl` | `bvid`, `cid`, `qn`, `fnval`, `fourk`; Android 端 `fnval=1488`，其他端 `fnval=0&platform=html5` | 可带 `SESSDATA`；高画质通常依赖登录账号权限 | `services/bilibili.ts:143-152` |
| 下载用播放地址 | GET | `https://api.bilibili.com/x/player/playurl` | `bvid`, `cid`, `qn`, `fnval=0`, `platform=html5` | 可带 `SESSDATA`；返回 `durl[0].url` 或 `backup_url` | `services/bilibili.ts:156-171` |
| UP 主卡片/统计 | GET | `https://api.bilibili.com/x/web-interface/card` | `mid` | 可带 Cookie | `services/bilibili.ts:174-184` |
| UP 主投稿列表 | GET | `https://api.bilibili.com/x/space/wbi/arc/search` | `mid`, `pn`, `ps`, `order=pubdate`, `platform=web`, `wts`, `w_rid` | WBI 签名 | `services/bilibili.ts:195-199` |
| 评论列表 | GET | `https://api.bilibili.com/x/v2/reply/main` | `oid=aid`, `type=1`, `mode=3/2`, `plat=1`, `pagination_str={"offset":...}` | 可带 Cookie | `services/bilibili.ts:230-244` |
| 视频缩略预览图 | GET | `https://api.bilibili.com/x/player/videoshot` | `bvid`, `cid`, `index=1` | 可带 Cookie | `services/bilibili.ts:252-257` |
| 二维码登录 - 生成 | GET | `https://passport.bilibili.com/x/passport-login/web/qrcode/generate` | 无 | 不需要登录；带 Referer | `services/bilibili.ts:261-266` |
| 二维码登录 - 轮询 | GET | `https://passport.bilibili.com/x/passport-login/web/qrcode/poll` | `qrcode_key` | 成功后从 `Set-Cookie` 或代理响应头 `X-Sessdata` 提取 `SESSDATA` | `services/bilibili.ts:269-294` |
| 直播推荐列表 | GET | `https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getMoreRecList` | `platform=web`, `page`, `page_size=20` | 可带 Cookie | `services/bilibili.ts:300-306` |
| 直播分区房间列表 | GET | `https://api.live.bilibili.com/room/v1/area/getRoomList` | `parent_area_id`, `area_id=0`, `page`, `page_size=20`, `sort_type=online`, `platform=web` | 可带 Cookie | `services/bilibili.ts:320-329` |
| 直播间详情 | GET | `https://api.live.bilibili.com/room/v1/Room/get_info` | `room_id` | 可带 Cookie | `services/bilibili.ts:344-348` |
| 直播主播信息 | GET | `https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room` | `roomid` | 可带 Cookie | `services/bilibili.ts:351-356` |
| 直播播放流 | GET | `https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo` | `room_id`, `protocol=0,1`, `format=0,1,2`, `codec=0`, `qn=10000`, `platform=android` | 可带 Cookie；返回 HLS/FLV 拼接字段 | `services/bilibili.ts:359-396` |
| 视频搜索 | GET | `https://api.bilibili.com/x/web-interface/wbi/search/type` | `keyword`, `search_type=video`, `page`, `page_size=20`, 可选 `order`, `wts`, `w_rid` | WBI 签名 | `services/bilibili.ts:407-417` |
| 直播历史弹幕 | GET | `https://api.live.bilibili.com/xlive/web-room/v1/dM/gethistory` | `roomid` | 可带 Cookie | `services/bilibili.ts:442-467` |
| 视频弹幕 XML | GET | `https://comment.bilibili.com/{cid}.xml` | 路径参数 `cid` | Native 带 Referer/User-Agent；返回可能 gzip/deflate 压缩 | `services/bilibili.ts:469-503` |
| 关注直播间列表 | GET | `https://api.live.bilibili.com/xlive/web-ucenter/v1/xfetter/FeedList` | `page=1`, `page_size=10`, `platform=web` | 需要 `SESSDATA` 才有意义 | `services/bilibili.ts:510-520` |
| 搜索建议 | GET | `https://api.bilibili.com/x/web-interface/search/suggest` | `term`, `main_ver=v1`, `highlight=` | 可带 Cookie | `services/bilibili.ts:533-539` |
| 热搜列表 | GET | `https://api.bilibili.com/x/web-interface/wbi/search/square` | `limit=10` | 代码中未做 WBI 签名 | `services/bilibili.ts:545-550` |

## 媒体与静态资源访问

| 类型 | 来源 | 处理方式 | 源码位置 |
|---|---|---|---|
| 视频 DASH/HTML5 播放 URL | `/x/player/playurl` 返回的 `dash` 或 `durl` 字段 | 播放器请求媒体时带 `Referer: https://www.bilibili.com` | `components/BigVideoCard.tsx:31`, `components/NativeVideoPlayer.tsx:42` |
| 视频下载 URL | `/x/player/playurl` 返回的 `durl[0].url` 或 `backup_url` | 下载时带 `Referer` 和 `Origin` | `hooks/useDownload.ts:77-90` |
| 直播 HLS/FLV URL | `/xlive/web-room/v2/index/getRoomPlayInfo` 返回的 `url_info + base_url + extra` | 播放器请求媒体时带 `Referer: https://live.bilibili.com` | `services/bilibili.ts:371-393`, `components/LivePlayer.tsx:27`, `components/LiveMiniPlayer.tsx:23` |
| 封面/头像/CDN 图片 | `*.hdslb.com` | Web 端改写成本地 `/bilibili-img/{host}/...` 代理，Native 强制 HTTPS | `utils/imageUrl.ts:7-16` |

## 登录、Cookie 与签名细节

| 项 | 项目实现 |
|---|---|
| `buvid3` | 本地随机生成类似 UUID 的值，保存到 `AsyncStorage`，请求时作为 Cookie 或 Web 代理头 `X-Buvid3` 发送。源码：`services/bilibili.ts:18-30`, `48-60` |
| `SESSDATA` | 通过二维码登录轮询成功后提取，保存在安全存储中；请求时作为 Cookie 或 Web 代理头 `X-Sessdata` 发送。源码：`services/bilibili.ts:48-60`, `269-294` |
| WBI key | 请求 `/x/web-interface/nav` 获取 `wbi_img.img_url` 和 `wbi_img.sub_url`，截取文件名得到 `imgKey`、`subKey`，缓存 12 小时。源码：`services/bilibili.ts:82-104` |
| WBI 签名 | 参数按 key 排序，追加 `wts`，用混淆后的 key 做 MD5，生成 `w_rid`。源码：`utils/wbi.ts:62-79` |

## 当前业务调用关系

| 页面/模块 | 调用的接口封装 |
|---|---|
| 首页视频流 | `getRecommendFeed`, `getLiveList` |
| 视频详情 | `getVideoDetail`, `getPlayUrl`, `getDanmaku`, `getUploaderStat`, `getVideoRelated`, `getComments`, `getVideoShot` |
| 下载 | `getPlayUrlForDownload` |
| UP 主页 | `getUploaderInfo`, `getUploaderVideos` |
| 搜索页 | `searchVideos`, `getSearchSuggest`, `getHotSearch` |
| 登录弹窗 | `generateQRCode`, `pollQRCode` |
| 直播列表/详情 | `getLiveList`, `getLiveRoomDetail`, `getLiveAnchorInfo`, `getLiveStreamUrl`, `getLiveDanmakuHistory` |
| 关注直播条 | `getFollowedLiveRooms` |
| 用户状态 | `getUserInfo` |

