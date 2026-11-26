# OpenList 影视重命名（Flutter 版）

一套代码同时出 Android 和 iOS：连接 OpenList 服务器，按 TMDB 标准批量重命名影视文件
（剧集 `剧名.S01E01.集名` / 电影 `片名 (年份)`），支持字幕同名文件同步改名。

## 目录

- `lib/` — Dart 源码（`engine.dart` 封装 OpenList / TMDB / TVmaze 调用，`state.dart` 管状态，`main_screen.dart` / `tools_panel.dart` / `edit_sheet.dart` 是界面）
- `android/` — Android 壳（包名 `dev.kobari.renamer`，debug keystore 与原生版共用签名）
- `ios/` — iOS 壳（未签名打包，SideStore 安装）

## 本地编译

```bash
flutter pub get
flutter build apk --release --split-per-abi   # Android，产物在 build/app/outputs/flutter-apk/
flutter build ipa --release --no-codesign     # iOS（只出 .xcarchive，需按 .github/workflows/flutter-ipa.yml 里那步自己打 IPA）
```

## CI

推到 `main` 即自动编译，见 `.github/workflows/flutter-apk.yml` 和 `.github/workflows/flutter-ipa.yml`：
编完会更新一份 Release 草稿（`v3.4.0`），APK（分架构）和 IPA 都在里面。

## 作者

KoBariDev — [GitHub](https://github.com/KoBariDev) · [博客](https://hub.131714.xyz)
