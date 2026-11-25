# OpenList 影视重命名

连接 OpenList 服务器，按 TMDB 标准批量重命名影视文件（剧集 `剧名.S01E01.集名` / 电影 `片名 (年份)`），
支持字幕同名文件同步改名，生成的库可直接被 Infuse / VidHub / Emby 海报墙识别。

- `ios/` — iPad 版（SwiftUI，iOS 16+，iPad Pro 2021 适配），见 [ios/README.md](ios/README.md)
- `android/` — Android 版（Kotlin + Jetpack Compose + Material 3，Android 8.0+）

## iOS 版 IPA（免签名，自签安装）

每次推送到 `main` 会自动在 GitHub Actions 的云端 Mac 上编译，
完成后在仓库 Actions 页面下载 `OpenListRenamer-ipa` 产物，用 SideStore / AltStore 安装。

也可以在 Actions 页面手动点 **Run workflow** 触发一次。

## Android 版本地编译

```bash
cd android
./gradlew :app:assembleDebug   # 或用 Android Studio 打开 android/
```

产物在 `android/app/build/outputs/apk/debug/`。

## 作者

KoBariDev — [GitHub](https://github.com/KoBariDev) · [博客](https://hub.131714.xyz) ·
[项目仓库 openlist-episode-renamer](https://github.com/kobaridev/openlist-episode-renamer)
