# OpenList 影视重命名

连接 OpenList 服务器，按 TMDB 标准批量重命名影视文件（剧集 `剧名.S01E01.集名` / 电影 `片名 (年份)`），
支持字幕同名文件同步改名，生成的库可直接被 Infuse / VidHub / Emby 海报墙识别。

当前主线是 **Flutter 版**（一套代码同时出 Android 和 iOS），`android/` / `ios/` 是旧的原生版，已冻结在 v3.4。

- `flutter/` — Flutter 版（Android + iOS），见 [flutter/README.md](flutter/README.md)
- `android/` — 旧原生 Android 版（Kotlin + Jetpack Compose + Material 3，Android 8.0+）
- `ios/` — 旧原生 iPad 版（SwiftUI，iOS 16+）

## 发布（Release 草稿）

每次推送到 `main`，GitHub Actions 会自动编译 Flutter 版，并更新一份 **Release 草稿**（`v3.4.0`，在仓库 Release 页面里找 Draft）：

- `Build Flutter APK`（ubuntu）：release 包，按架构分包（arm64-v8a / armeabi-v7a / x86_64），用仓库里的 debug keystore 签名，可直接覆盖安装
- `Build Flutter IPA`（macOS）：未签名 IPA，用 SideStore / AltStore 安装

想手动触发一次，在 Actions 页面点 **Run workflow**。

## 作者

KoBariDev — [GitHub](https://github.com/KoBariDev) · [博客](https://hub.131714.xyz) ·
[项目仓库 openlist-episode-renamer-mobile](https://github.com/kobaridev/openlist-episode-renamer-mobile)
