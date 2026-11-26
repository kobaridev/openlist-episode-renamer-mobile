import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'state.dart';
import 'widgets.dart';

/// Single-file edit bottom sheet (port of the ModalBottomSheet in
/// MainScreen): its own TMDB search (movie + TV) that never disturbs the
/// tools panel selection; "重命名此文件" renames just this row (including
/// its same-name subtitle files).
class EditSheet extends StatefulWidget {
  final AppState state;
  final RowState row;
  final void Function(String) showSnack;
  final VoidCallback onSingleRename;

  const EditSheet({
    super.key,
    required this.state,
    required this.row,
    required this.showSnack,
    required this.onSingleRename,
  });

  @override
  State<EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<EditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _seasonCtrl;
  late final TextEditingController _episodeCtrl;
  late final TextEditingController _epTitleCtrl;
  late final TextEditingController _tagsCtrl;
  final _searchCtrl = TextEditingController();
  List<dynamic> _results = [];
  bool _searching = false;
  Timer? _debounce;

  AppState get state => widget.state;
  RowState get row => widget.row;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: row.title)
      ..addListener(() {
        row.title = _titleCtrl.text;
        state.syncEpisodes();
        state.touch();
      });
    _yearCtrl = TextEditingController(text: row.year)
      ..addListener(() {
        row.year = _digitsOnly(_yearCtrl.text);
        state.syncEpisodes();
        state.touch();
      });
    _seasonCtrl = TextEditingController(text: row.season)
      ..addListener(() {
        row.season = _digitsOnly(_seasonCtrl.text);
        state.syncEpisodes();
        state.touch();
      });
    _episodeCtrl = TextEditingController(text: row.episode)
      ..addListener(() {
        row.episode = _digitsOnly(_episodeCtrl.text);
        state.syncEpisodes();
        state.touch();
      });
    _epTitleCtrl = TextEditingController(text: row.epTitle)
      ..addListener(() {
        row.epTitle = _epTitleCtrl.text;
        state.syncEpisodes();
        state.touch();
      });
    _tagsCtrl = TextEditingController(text: row.tags)
      ..addListener(() {
        row.tags = _tagsCtrl.text;
        state.syncEpisodes();
        state.touch();
      });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _yearCtrl.dispose();
    _seasonCtrl.dispose();
    _episodeCtrl.dispose();
    _epTitleCtrl.dispose();
    _tagsCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onKeywordChanged(String v) {
    _debounce?.cancel();
    final kw = v.trim();
    if (kw.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (_searchCtrl.text.trim() == kw) _doSearch();
    });
  }

  Future<void> _doSearch() async {
    final kw = _searchCtrl.text.trim();
    if (kw.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final raw = await state.searchSingle(kw);
      if (!mounted) return;
      setState(() => _results = raw);
      if (raw.isEmpty) widget.showSnack('没有搜到结果');
    } catch (e) {
      widget.showSnack('搜索失败：${_short(e)}');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _short(Object e) {
    final m = e.toString();
    return m.startsWith('Exception: ') ? m.substring(11) : m;
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _onPick(dynamic res) async {
    _titleCtrl.text = res.name;
    if (state.mediaType == 'movie') {
      _yearCtrl.text = res.year;
      state.syncEpisodes();
      state.touch();
      widget.showSnack('已填入电影名');
      return;
    }
    state.syncEpisodes();
    state.touch();
    try {
      final season = int.tryParse(row.season) ?? 1;
      final eps = await state.fetchEpisodesFor(res, season);
      final t = eps[row.episode];
      if (state.useEpisodeTitle && t != null) {
        _epTitleCtrl.text = t.trim();
      }
      state.syncEpisodes();
      state.touch();
      widget.showSnack('已填入剧名和集名');
    } catch (e) {
      widget.showSnack('获取集名失败：${_short(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMovie = state.mediaType == 'movie';
    final curTags = _tagsCtrl.text
        .split(RegExp(r'[,，;；|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
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
            Text(
              row.name,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (row.names.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '同名文件共 ${row.names.length} 个（${row.names.map((n) => n.contains('.') ? n.substring(n.lastIndexOf('.') + 1) : n).join('、')}），改名会一起改',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.primary),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleCtrl,
              decoration:
                  InputDecoration(labelText: isMovie ? '电影名' : '剧名'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: CompactInput(
                    value: _searchCtrl.text,
                    onChanged: (v) {
                      _searchCtrl.text = v;
                      _onKeywordChanged(v);
                    },
                    placeholder:
                        isMovie ? '搜索电影名，只填这一行' : '搜索剧名，只填这一行',
                    height: 42,
                    onSearch: _doSearch,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 42,
                  height: 42,
                  child: FilledButton(
                    onPressed: _searching ? null : _doSearch,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search, size: 18),
                  ),
                ),
              ],
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 8),
              SearchResultList(
                results: _results.cast(),
                selectedId: null,
                isMovie: isMovie,
                onPick: _onPick,
              ),
            ],
            const SizedBox(height: 10),
            if (isMovie)
              TextField(
                controller: _yearCtrl,
                decoration: const InputDecoration(labelText: '年份'),
                keyboardType: TextInputType.number,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _seasonCtrl,
                      decoration: const InputDecoration(labelText: '季'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _episodeCtrl,
                      decoration: const InputDecoration(labelText: '集'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            if (!isMovie) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _epTitleCtrl,
                decoration: const InputDecoration(labelText: '集名（可选）'),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _tagsCtrl,
              decoration: const InputDecoration(labelText: '媒体参数，逗号分隔'),
            ),
            if (curTags.isNotEmpty) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: curTags.map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        selected: true,
                        onDeleted: () {
                          _tagsCtrl.text =
                              curTags.where((e) => e != t).join(',');
                        },
                        label: Text(t),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '新名：${state.previewName(row)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.primary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: state.previewName(row) != row.name
                        ? widget.onSingleRename
                        : null,
                    child: const Text('重命名此文件'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Batch edit bottom sheet (port of the batchOpen sheet in MainScreen):
/// blank fields are left unchanged; a start episode numbers the selected
/// rows in list order.
class BatchEditSheet extends StatefulWidget {
  final AppState state;
  final void Function(String) showSnack;
  const BatchEditSheet(
      {super.key, required this.state, required this.showSnack});

  @override
  State<BatchEditSheet> createState() => _BatchEditSheetState();
}

class _BatchEditSheetState extends State<BatchEditSheet> {
  String _title = '';
  String _season = '';
  String _start = '';
  String _year = '';
  String _tags = '';

  AppState get state => widget.state;

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  void _apply() {
    final targets =
        state.rows.where((r) => state.selected.contains(r.name)).toList();
    int? ep = int.tryParse(_start);
    for (final r in targets) {
      if (_title.trim().isNotEmpty) r.title = _title.trim();
      if (state.mediaType == 'movie') {
        if (_year.isNotEmpty) r.year = _year;
      } else {
        if (_season.isNotEmpty) r.season = _season;
        if (ep != null) {
          r.episode = ep.toString();
          ep++;
        }
        final t = state.tmdbEpisodes[r.episode];
        if (state.useEpisodeTitle && t != null) r.epTitle = t.trim();
      }
      if (_tags.isNotEmpty) r.tags = _tags;
    }
    state.syncEpisodes();
    state.touch();
    Navigator.of(context).pop();
    widget.showSnack('已批量更新 ${targets.length} 个文件');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMovie = state.mediaType == 'movie';
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
            Text(
              '批量编辑 ${state.selected.length} 个文件',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '留空的字段不改；填了起始集号会按列表顺序连续编号。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => _title = v,
              decoration:
                  InputDecoration(labelText: isMovie ? '统一电影名' : '统一剧名'),
            ),
            const SizedBox(height: 10),
            if (isMovie)
              TextField(
                onChanged: (v) => setState(() => _year = _digitsOnly(v)),
                decoration: const InputDecoration(labelText: '统一年份'),
                keyboardType: TextInputType.number,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) =>
                          setState(() => _season = _digitsOnly(v)),
                      decoration: const InputDecoration(labelText: '统一季号'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (v) =>
                          setState(() => _start = _digitsOnly(v)),
                      decoration: const InputDecoration(labelText: '起始集号'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            TextField(
              onChanged: (v) => _tags = v,
              decoration:
                  const InputDecoration(labelText: '统一媒体参数，逗号分隔'),
            ),
            if (!isMovie && state.tmdbEpisodes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '已刮削到 ${state.tmdbEpisodes.length} 集集名，应用时按集号自动填入。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.primary),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _apply,
                child: const Text('应用到所选'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
