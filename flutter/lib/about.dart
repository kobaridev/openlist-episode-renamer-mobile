import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// About page (port of SettingsDialog in MainActivity.kt): text only —
/// description, feature list, author bio, plain links. Version is read
/// from the build, never hardcoded. No Settings page.
class AboutSheet extends StatefulWidget {
  const AboutSheet({super.key});

  @override
  State<AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends State<AboutSheet> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
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
    final bodySmallDim = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    const features = [
      '剧集 / 电影两种模式，进目录自动识别，也可手动切换',
      'TMDB 搜索，点海报自动填入剧名与集名；TMDB 不行时自动换 TVmaze',
      '批量编号、批量编辑，也支持单个文件搜索与重命名',
      '媒体参数自动识别：分辨率、HDR、编码、音频、字幕语言',
      '同名视频与字幕文件按集号合并，一起改名',
      '目录缓存、按目录记住刮削结果，重复进目录不用重新加载',
    ];
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: 28 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text('关于', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              'OpenList 影视重命名${_version.isEmpty ? '' : ' · v$_version'}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              '连接你的 OpenList，把杂乱的影视文件名一键改成 TMDB 标准格式。剧集按「剧名.S01E01.集名」命名，电影按「片名 (年份)」命名，改完直接在 Infuse、VidHub、Emby 里出海报墙。',
            ),
            const SizedBox(height: 14),
            Text('功能', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $f', style: bodySmallDim),
                )),
            const SizedBox(height: 14),
            Text('作者', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'KoBariDev',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'openlist-episode-renamer 的作者。平时折腾 NAS 与影视库，博客上有相关记录，GitHub 上有 10 个原创项目。',
              style: bodySmallDim,
            ),
            const SizedBox(height: 8),
            _Link(
              'GitHub：github.com/KoBariDev',
              () => _openUrl('https://github.com/KoBariDev'),
            ),
            _Link(
              '博客：hub.131714.xyz',
              () => _openUrl('https://hub.131714.xyz'),
            ),
            _Link(
              '项目仓库：github.com/KoBariDev/openlist-episode-renamer',
              () => _openUrl(
                  'https://github.com/KoBariDev/openlist-episode-renamer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _Link(this.text, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      ),
    );
  }
}
