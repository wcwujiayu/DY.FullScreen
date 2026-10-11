# DY.FullScreen 新手上传和自动构建指南（Windows）

## 1. 仓库

仓库地址： https://github.com/wcwujiayu/DY.FullScreen

项目文件应包含隐藏目录 `.github/workflows/build.yml`。如果已通过 GitHub 连接直接上传源码，无需再用 GitHub Desktop 手动复制。

## 2. 运行自动构建

1. 打开仓库并点击顶部 **Actions**。
2. 选择 **Build DY.FullScreen**。如果 GitHub 提示启用 Actions，请点击启用。
3. 等待最新的运行记录结束。绿色勾代表工作流完成；红色叉代表失败。
4. 打开该运行记录，在页面底部 **Artifacts** 下载 `DY.FullScreen-build` 并解压。

预期文件：
- `com.dy.fullscreen_0.1.0_iphoneos-arm-rootful.deb`
- `com.dy.fullscreen_0.1.0_iphoneos-arm64-rootless.deb`
- `com.dy.fullscreen_0.1.0_iphoneos-arm64e-roothide.deb`
- `DY.FullScreen_0.1.0.dylib`
- `DY.FullScreen.dylib`
- `DY.FullScreen-TrollFools-0.1.0.zip`
- `SHA256SUMS.txt`

## 3. 发布长期下载版本（可选）

提交代码后，推送一个版本标签（例如 `v0.1.0`）会触发构建，并尝试将构建产物附加到 GitHub Release。修改代码后请升级 `control` 文件的 Version，再使用新的 tag。

## 4. 导入 TrollFools

你的环境是 iOS 16.1 + 抖音 40.7.0 + TrollFools。优先测试独立 `.dylib` 或 ZIP；不要把 `.deb` 当作首选注入文件。测试前先停用其它会修改抖音全屏布局的插件。若出现闪退或错位加重，请在 TrollFools 中停用插件并重启抖音。

## 5. 出错时

进入 **Actions → 失败的运行 → 第一个失败步骤**，展开日志，复制末尾 30–60 行报错文本。不要发送 GitHub 密码、个人访问令牌或其他密钥。

## 重要提醒

本项目为实验版。构建通过只说明编译/打包成功，不代表已在真机验证全屏位置。
