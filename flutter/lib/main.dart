import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';
import 'main_screen.dart';
import 'state.dart';
import 'theme.dart';

/// OpenList 影视重命名 — Flutter 版（与安卓原生版、iOS 版共用一个仓库）。
/// 功能与原生 v3.4 对齐：登录、目录浏览、按集号分组、TMDB/TVmaze 刮削、
/// 剧集/电影模式、批量与单文件重命名。

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(RenamerApp(prefs: prefs));
}

class RenamerApp extends StatefulWidget {
  final SharedPreferences prefs;
  const RenamerApp({super.key, required this.prefs});

  @override
  State<RenamerApp> createState() => _RenamerAppState();
}

class _RenamerAppState extends State<RenamerApp> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState(widget.prefs);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        return MaterialApp(
          title: 'OpenList 影视重命名',
          theme: renamerTheme(false),
          darkTheme: renamerTheme(true),
          themeMode: _state.darkTheme ? ThemeMode.dark : ThemeMode.light,
          home: GradientBackground(
            dark: _state.darkTheme,
            child: _state.loggedIn
                ? MainScreen(_state)
                : LoginScreen(_state),
          ),
        );
      },
    );
  }
}
