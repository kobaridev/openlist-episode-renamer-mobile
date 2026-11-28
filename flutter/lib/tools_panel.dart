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
          // NOTE: do NOT use FilterChip here — in Material 3 the selected
          // chip replaces its icon with a checkmark in a dark circle, which
          // looks broken and hides which option is selected. A segmented
          // control keeps both icons always visible.
          _MediaTypeSegmented(state: state),
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
            // Source note: TVmaze only carries English/original titles,
            // so an all-English list means TMDB didn't respond and the
            // app fell back to TVmaze (Chinese names are matched back
            // from TMDB where possible).
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                state.tmdbSource == 'tvmaze'
                    ? '来源：TVmaze（仅英文名，已尽量匹配 TMDB 中文名）'
                    : '来源：TMDB',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
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

/// Segmented 剧集/电影 switch. The selected segment keeps its icon visible
/// (primary on primaryContainer); the unselected one is muted. No checkmark.
class _MediaTypeSegmented extends StatelessWidget {
  const _MediaTypeSegmented({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            context,
            selected: state.mediaType == 'tv',
            icon: Icons.tv,
            label: '剧集',
            onTap: () => state.setMediaType('tv'),
          ),
          const SizedBox(width: 4),
          _segment(
            context,
            selected: state.mediaType == 'movie',
            icon: Icons.movie,
            label: '电影',
            onTap: () => state.setMediaType('movie'),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
