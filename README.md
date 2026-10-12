# DY.FullScreen

让抖音首页视频撑满整块屏幕的 Theos 插件，仅在 **抖音 iOS 40.7.0** 上测试。
**仅供学习交流，禁止用于商业用途。**

> **版本 0.4.6** ｜ 目标环境：iOS 16.1 · 抖音 40.7.0 · TrollStore + TrollFools 注入
> 抖音设置项名称：**「启用全屏」** ｜ 侧边栏入口按钮：**「全屏设置」**

---

## 功能总览

### 全屏

- 首页视频 / 图集画布撑满整块屏幕（视频列表、互动层、播放器画面三处高度补偿）
- 底栏 TabBar 背景透明，按钮保留可见可点
- 进度条黑色背景线清除
- 开播前推流预览的播放器高度匹配（不平移文案与按钮）
- 信息流直播卡片：视频撑满卡片；账号与文案停在底栏上方；「进入直播间 + 横屏」按钮组整体水平居中

### 透明化

- 视频底部信息 / 评论 dock（我-作品、我-喜欢、全部视频里的浏览数、图文分析、评论输入栏）
- 「相关搜索」/「合集」胶囊卡片背景
- 兼容毛玻璃底栏（`UIVisualEffectView` 置空，内容保留）
- 只清背景：文字、图标、点击区域一律不动
- 直播间与开播预览不受影响

### 设置与诊断

- 侧边栏「全屏设置」按钮：插件开关 + 运行诊断
- 抖音原生设置页「启用全屏」开关
- 诊断面板：各 Hook 安装状态、调整次数、版本匹配情况

### 保护机制

- 真正进入直播间时，跳过所有尺寸与透明处理
- 个人主页不参与尺寸修正，仅做透明化
- 直播卡片内容识别只处理含文字 / 控件的视图，视频层与背景层不碰

---

## 安装

1. 从 Release 下载 `DY.FullScreen.dylib`
2. 在 TrollFools 中停用并移除旧版，再注入新 dylib
3. 打开抖音侧边栏点「全屏设置」，或到抖音「设置」里找「启用全屏」
4. 测试前先停用其他会修改视频尺寸 / 布局的插件，避免 Hook 冲突

## 构建

支持三种打包方案，产物由 GitHub Actions 自动构建：

```bash
make package SCHEME=rootless FINALPACKAGE=1   # TrollFools 常用
make package SCHEME=rootful  FINALPACKAGE=1
make package SCHEME=roothide FINALPACKAGE=1
```

版本号唯一来源为 `control` 的 `Version` 字段，CI 动态读取，不重复维护。

## 项目结构

| 模块 | 职责 |
|---|---|
| `Tweak.m` | 入口：constructor 与 hook 安装调度 |
| `DYFSCommon` | 常量、runtime 工具、跨模块状态、抖音私有类名清单 |
| `DYFSContext` | 上下文守卫（个人主页 / 直播间 / 推流预览 / 详情页） |
| `DYFSLayout` | 尺寸修正 |
| `DYFSChrome` | 底栏背景透明、进度条黑线 |
| `DYFSSettings` | 设置入口与运行诊断 |
| `DYFSTransparency` | 底栏 / 卡片透明化 |
| `DYLiveFeedFullscreen` | 信息流直播卡片 |

抖音改版导致类名变化时，只需更新 `DYFSCommon.m` 与 `DYFSContext.m` 顶部的常量清单。

## 免责声明

仅供学习交流，禁止用于商业用途。请遵守所在地法律法规及相关应用的使用条款。
本项目不隶属于或代表抖音、字节跳动或 TrollFools。
