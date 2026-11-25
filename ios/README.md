# OpenListRenamer for iOS / iPad

OpenList 剧集重命名工具的 iOS 版（SwiftUI），由 Android 版（Kotlin + Jetpack Compose）移植而来。

- **目标设备**：iPad Pro 2021（M1，12.9 寸 / 11 寸），iPad-only，iOS 16.0+，支持横竖屏与分屏多任务
- **功能**：OpenList 登录（自动登录）、目录浏览、按 SxxEyy 分组、剧集/电影模式、TMDB 搜索与集名刮削（TVmaze 兜底）、批量编号、媒体参数识别、批量/单文件重命名、关于页 GitHub 卡片
- **零第三方依赖**：纯 SwiftUI + Foundation + URLSession

## 为什么这里没有现成的 .ipa

IPA 只能在 macOS + Xcode 下编译，这台 Linux 机器编不出来。本仓库提供完整源码 + 工程文件，IPA 由 GitHub Actions 在云端 Mac 上编译。

## 拿 IPA 的步骤

1. 把本目录内容推到你的 GitHub 仓库（例如 `kobaridev/openlist-episode-renamer` 的 `ios` 分支或单独仓库）
2. 打开仓库的 **Actions** → **Build IPA**，等跑完（约 5–10 分钟）
3. 下载产物 **OpenListRenamer-ipa**（`OpenListRenamer.ipa`，未签名）
4. 用 **SideStore / AltStore** 安装到 iPad（会用你自己的 Apple ID 重签名）

也可以在 Mac 上直接打开 `OpenListRenamer.xcodeproj` 编译运行。

## 版本

版本号与 Android 版同步，当前 v3.2（build 23），在 `OpenListRenamer.xcodeproj` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 里改；关于页的版本号是动态读 Bundle 的，不用另外改代码。
