# DY.FullScreen

用于调整DY UI 的 Theos/Logos Tweak，仅在 **40.7.0** 中测试。  
**仅供学习交流，禁止用于商业用途。**

> 实验版本 0.3.4。目标环境：iOS 16.1、抖音 iOS 40.7.0、TrollStore + TrollFools。“首页全屏（DY.FullScreen）”开关位于抖音原生设置列表。0.3.4 在扩展首页视频列表时，将互动控制器整体限制在底栏上方的可用区域，不逐项改动点赞、评论、分享按钮或文案；仍需在目标设备验证实际布局。

## 自动构建

仓库使用 Theos/Logos 构建流程，并尝试生成 rootful、rootless、roothide 三种 Debian 包，以及 TrollFools 使用的动态库。推送代码后查看仓库 Actions 页面中的构建任务；成功后在该次运行记录底部 Artifacts 下载构建结果。

预期文件包括三种 .deb、DY.FullScreen_0.3.4.dylib、DY.FullScreen.dylib、DY.FullScreen-TrollFools-0.3.4.zip 和 SHA256SUMS.txt。版本标签（例如 v0.3.4）用于触发 GitHub Release 发布流程。

## 安装与测试

1. 从 Actions Artifacts 下载构建包并解压。
2. 在 TrollFools 中停用并移除旧版，再注入本次构建的 DY.FullScreen.dylib（或 ZIP 内的 dylib）；.deb 是 Debian 包格式，不是首选注入文件。
3. 打开抖音侧边栏，在系统“设置”入口旁点击“全屏”，检查开关和“运行诊断”。
4. 测试前停用其他会修改抖音布局的插件，避免 Hook 冲突。
5. 第一轮只检查首页视频与点赞、评论、分享等控件是否对齐。
6. 若闪退或错位加重，立即在 TrollFools 停用本插件并重启抖音。

## 免责声明

仅供学习交流，禁止用于商业用途。请遵守所在地法律法规及相关应用的使用条款。本项目不隶属于或代表抖音、字节跳动或 TrollFools。
