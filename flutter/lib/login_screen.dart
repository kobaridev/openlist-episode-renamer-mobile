import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'state.dart';
import 'widgets.dart';

/// Port of LoginScreen in MainActivity.kt: server address / username /
/// password with cloud / person / lock leading icons, empty-field
/// validation, saved credentials, auto-login when all three are saved.
class LoginScreen extends StatefulWidget {
  final AppState state;
  const LoginScreen(this.state, {super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  String? _error;
  bool _busy = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    final prefs = state.prefs;
    final savedUrl = prefs.getString('base_url') ?? '';
    _urlCtrl = TextEditingController(
        text: savedUrl.isEmpty ? '127.0.0.1:5244' : savedUrl);
    _userCtrl = TextEditingController(text: prefs.getString('username') ?? '');
    _passCtrl = TextEditingController(text: prefs.getString('password') ?? '');
    // Auto-login when all three saved values are present.
    if (_urlCtrl.text.isNotEmpty &&
        _userCtrl.text.isNotEmpty &&
        _passCtrl.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _attempt());
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _attempt() async {
    if (_busy) return;
    if (_urlCtrl.text.trim().isEmpty) {
      setState(() => _error = '服务器地址不能为空');
      return;
    }
    if (_userCtrl.text.trim().isEmpty) {
      setState(() => _error = '用户名不能为空');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      setState(() => _error = '密码不能为空');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await state.doLogin(
        _urlCtrl.text, _userCtrl.text, _passCtrl.text);
    if (!mounted) return;
    setState(() {
      _error = err;
      _busy = false;
    });
  }

  Future<void> _openUrl(String u) async {
    final uri = Uri.parse(u);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Image.asset(
                    'assets/login_logo.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Icon(
                      Icons.movie,
                      size: 56,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'OpenList 影视重命名',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '连接你的 OpenList 服务器',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: '例如 192.168.1.10:5244',
                  prefixIcon: Icon(Icons.cloud),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passCtrl,
                decoration: const InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _attempt(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.error),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : _attempt,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('连接'),
                ),
              ),
              const SizedBox(height: 30),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ShieldBadge('GitHub', 'KoBariDev',
                      () => _openUrl('https://github.com/KoBariDev')),
                  ShieldBadge('Blog', 'hub.131714.xyz',
                      () => _openUrl('https://hub.131714.xyz')),
                  ShieldBadge('Repo', 'openlist-episode-renamer',
                      () => _openUrl(
                          'https://github.com/KoBariDev/openlist-episode-renamer')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
