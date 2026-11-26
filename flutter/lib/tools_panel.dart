import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Port of ToolsPanel in MainActivity.kt: 剧集/电影 switch, numbering,
/// TMDB search (debounce + cache + exact-title boost), episode-title
/// toggle, media-parameter chips.
class ToolsPanel extends StatefulWidget {
  final AppState state;
  final void Function(String) showSnack;
  const ToolsPanel({super.key, required this.state, required this.showSnack});

  @override
  State<ToolsPanel> createState() => _ToolsPanelState();
}

class _ToolsPanelState extends State<ToolsPanel> {
  Timer? _kwTimer;
  Timer? _seasonTimer;
  String _lastKeyword = '';
  String _lastMediaType = '';
  String _lastSeason = '';
  String _custom = '';

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _lastKeyword = state.tmdbKeyword;
    _lastMediaType = state.mediaType;
    _lastSeason = state.tmdbSeason;
    state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _kwTimer?.cancel();
    _seasonTimer?.cancel();
    state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    // Type-ahead: search 600ms after the user stops typing.
    if (state.tmdbKeyword != _lastKeyword) {
      _lastKeyword = state.tmdbKeyword;
      _kwTimer?.cancel();
      final kw = state.tmdbKeyword.trim();
      if (kw.isNotEmpty) {
        _kwTimer = Timer(const Duration(milliseconds: 600), () {
          if (state.tmdbKeyword.trim() == kw) _doSearch();
        });
      }
    }
    // Type switched while a query is typed: re-search with the new type's
    // endpoint (otherwise the old type's results stay on screen, mislabeled
    // as the new type).
    if (state.mediaType != _lastMediaType) {
      _lastMediaType = state.mediaType;
      if (state.tmdbKeyword.trim().isNotEmpty) {
        state.tmdbSelected = null;
        state.tmdbEpisodes = {};
        state.tmdbResults = [];
        state.touch();
        _doSearch();
      }
    }
    // Season changed while a show is selected: re-scrape that season.
    if (state.tmdbSeason != _lastSeason) {
      _seasonTimer?.cancel();
      final season = state.tmdbSeason;
      _seasonTimer = Timer(const Duration(milliseconds: 500), () {
        _lastSeason = state.tmdbSeason;
        if (state.mediaType == 'tv' &&
            state.tmdbSelected != null &&
            state.tmdbSeason.isNotEmpty) {
          _fetchEpisodes();
        }
      });
      // Keep _lastSeason in sync when the timer has not fired yet.
      if (season.isEmpty || state.tmdbSelected == null) {
        _lastSeason = season;
      }
    }
  }

  Future<void> _doSearch() async {
    if (state.tmdbKeyword.trim().isEmpty || state.tmdbSearching) return;
    state.tmdbSearching = true;
    state.touch();
    try {
      final results = await state.doSearch();
      if (results.isEmpty) widget.showSnack('没有搜到结果');
    } catch (e) {
      widget.showSnack('搜索失败：${_short(e)}');
    } finally {
      state.tmdbSearching = false;
      state.touch();
    }
  }

  Future<void> _fetchEpisodes() async {
    if (state.tmdbFetching) return;
    try {
      await state.fetchSelectedEpisodes();
      widget.showSnack(state.mediaType == 'movie' ? '已填入电影名' : '已填入剧名和集名');
    } catch (e) {
      widget.showSnack('获取集名失败：${_short(e)}');
    }
  }

  String _short(Object e) {
    final m = e.toString();
    return m.startsWith('Exception: ') ? m.substring(11) : m;
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Media type: TV series vs movie (Filmix-style split).
          Row(
            children: [
              FilterChip(
                selected: state.mediaType == 'tv',
                onSelected: (_) => state.setMediaType('tv'),
                label: const Text('剧集'),
                avatar: const Icon(Icons.tv, size: 16),
              ),
              const SizedBox(width: 6),
              FilterChip(
                selected: state.mediaType == 'movie',
                onSelected: (_) => state.setMediaType('movie'),
                label: const Text('电影'),
                avatar: const Icon(Icons.movie, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Numbering row.
          if (state.mediaType == 'tv')
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: LabeledInput(
                    value: state.tmdbSeason,
                    onChanged: (v) {
                      state.tmdbSeason = _digitsOnly(v);
                      state.touch();
                    },
                    label: '季',
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LabeledInput(
                    value: state.epStart,
                    onChanged: (v) {
                      state.epStart = _digitsOnly(v);
                      state.saveSetting();
                      state.touch();
                    },
                    label: '起始集',
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 42,
                  child: FilledButton(
                    onPressed: () {
                      state.applyEpisodeNumbers();
                      state.touch();
                      widget.showSnack('已按顺序编号');
                    },
                    child: const Text('编号'),
                  ),
                ),
              ],
            ),
          if (state.mediaType == 'tv') const SizedBox(height: 8),
          // TMDB search row.
          Row(
            children: [
              Expanded(
                child: CompactInput(
                  value: state.tmdbKeyword,
                  onChanged: (v) {
                    state.tmdbKeyword = v;
                    state.touch();
                  },
                  placeholder:
                      state.mediaType == 'movie' ? 'TMDB 搜索电影名' : 'TMDB 搜索剧名',
                  height: 46,
                  onSearch: _doSearch,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 46,
                height: 46,
                child: FilledButton(
                  onPressed: state.tmdbSearching ? null : _doSearch,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  child: state.tmdbSearching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search, size: 20),
                ),
              ),
            ],
          ),
          if (state.tmdbResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            SearchResultList(
              results: state.tmdbResults,
              selectedId: state.tmdbSelected?.id,
              isMovie: state.mediaType == 'movie',
              onPick: (res) async {
                state.tmdbSelected = res;
                state.touch();
                await _fetchEpisodes();
              },
            ),
          ],
          if (state.mediaType == 'tv')
            Row(
              children: [
                Checkbox(
                  value: state.useEpisodeTitle,
                  onChanged: (v) {
                    state.useEpisodeTitle = v ?? true;
                    state.saveSetting();
                    state.touch();
                  },
                ),
                const Text('文件名包含集名',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
          // Media params: presets.
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: presets.map((p) {
                final sel = state.mediaParams.contains(p);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    selected: sel,
                    onSelected: (_) {
                      state.mediaParams = sel
                          ? state.mediaParams.where((e) => e != p).toList()
                          : [...state.mediaParams, p];
                      state.touch();
                    },
                    label: Text(p),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CompactInput(
                  value: _custom,
                  onChanged: (v) => setState(() => _custom = v),
                  placeholder: '自定义参数',
                  height: 46,
                ),
              ),
              IconButton(
                onPressed: () {
                  if (_custom.trim().isNotEmpty) {
                    state.mediaParams = [...state.mediaParams, _custom.trim()];
                    setState(() => _custom = '');
                    state.touch();
                  }
                },
                icon: const Icon(Icons.add),
              ),
              FilledButton(
                onPressed: () {
                  state.applyTags();
                  state.touch();
                  widget.showSnack('参数已应用到全部文件');
                },
                child: const Text('应用参数'),
              ),
            ],
          ),
          if (state.mediaParams.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: state.mediaParams.map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InputChip(
                      selected: true,
                      onDeleted: () {
                        state.mediaParams =
                            state.mediaParams.where((e) => e != p).toList();
                        state.touch();
                      },
                      label: Text(p),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
