# DY.FullScreen

用于调整DY UI 的 Theos/Logos Tweak，仅在 **40.7.0** 中测试。  
**仅供学习交流，禁止用于商业用途。**

> 实验版本 0.3.18。目标环境：iOS 16.1、抖音 iOS 40.7.0、TrollStore + TrollFools。原生设置项主标题为“首页全屏”，下方副标题为“胖胖专属”。本版本保留原有普通视频、图集、个人主页、喜欢/收藏页面及卡片透明处理逻辑；直播卡片新增独立交互布局模块，移植 DYYY 的 `AWEPlayInteractionViewController -viewDidLayoutSubviews` 高度规则，只调整被识别为直播信息流卡片的交互容器，以便卡片下方文案及功能区域按底部导航栏可用高度布局。此模块不调整播放器画面、`contentView` 或任意单独按钮的位置，不改 `Tweak.m` 中既有的普通视频全屏逻辑；进入正式直播间也不在此模块的调整范围内。该布局仍需在抖音 40.7.0 真机验证。

## 自动构建

仓库使用 Theos/Logos 构建流程，生成 rootful、rootless、roothide 三种 Debian 包，以及 TrollFools 使用的动态库。推送到 `main` 或本次开发分支后查看仓库 Actions 页面中的构建任务；成功后在该次运行记录底部 Artifacts 下载构建结果。

预期文件包括三种 .deb、`DY.FullScreen_0.3.18.dylib`、`DY.FullScreen.dylib`、`DY.FullScreen-TrollFools-0.3.18.zip` 和 `SHA256SUMS.txt`。版本标签（例如 `v0.3.18`）用于触发 GitHub Release 发布流程。

请以本次 Actions 运行生成的 0.3.18 文件为准，不要继续注入先前 0.3.16 的工件。此次开发分支为 `dev/live-feed-fullscreen-0.3.16`，版本文件名与分支名独立。

## 安装与测试

1. 从 Actions Artifacts 下载构建包并解压。
2. 在 TrollFools 中停用并移除旧版，再注入本次构建的 `DY.FullScreen.dylib`（或 ZIP 内的 dylib）；.deb 是 Debian 包格式，不是首选注入文件。
3. 打开抖音侧边栏，在系统“设置”入口旁点击“胖胖专属”，检查开关和“运行诊断”。
4. 首先只启用 DY.FullScreen，确保已有功能正常；再检查推荐页、关注页、附近页直播卡片下方的文案和功能区域是否与 DYYY 的位置一致；视频画面本身不应被本模块放大。
5. 验证直播卡片上的点赞、评论、关注、文案等交互位置，再点击进入正式直播间，确认主播画面、评论、礼物与底部互动未变化。
6. 检查个人主页作品、喜欢/收藏视频的底部评论输入栏背景，以及视频里的“相关搜索”和“合集”卡片背景。
7. 若闪退或错位加重，立即在 TrollFools 停用本插件并重启抖音。

## 免责声明

仅供学习交流，禁止用于商业用途。请遵守所在地法律法规及相关应用的使用条款。本项目不隶属于或代表抖音、字节跳动或 TrollFools。
