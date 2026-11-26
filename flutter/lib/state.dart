import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';

const List<String> mediaExts = [
  'mp4', 'mkv', 'avi', 'ts', 'flv', 'wmv', 'mov', 'm4v', 'webm', 'mpg',
  'mpeg', '3gp', 'asf', 'srt', 'ass', 'ssa',
];
final RegExp mediaRe = RegExp(
    '\\.(${mediaExts.join('|')})\$',
    caseSensitive: false);
const List<String> presets = [
  '1080p', '4K', 'HDR', 'HDR10', 'DV', 'DTS-HD', '中英字幕',
];

String pad2(String n) => (n.isEmpty ? '0' : n).padLeft(2, '0');

String humanSize(int b) {
  if (b <= 0) return '';
  if (b < 1024) return '$b B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = -1;
  do {
    v /= 1024;
    i++;
  } while (v >= 1024 && i < u.length - 1);
  return '${v.toStringAsFixed(1)} ${u[i]}';
}

String parentOf(String p) {
  final t = p.replaceAll(RegExp(r'/+$'), '');
  final i = t.lastIndexOf('/');
  return i <= 0 ? '/' : t.substring(0, i);
}

String dirNameOf(String p) {
  final parts = p.replaceAll(RegExp(r'/+$'), '').split('/').where((e) => e.isNotEmpty).toList();
  return parts.isEmpty ? '' : parts.last;
}

int natCmp(String a, String b) {
  final ra = RegExp(r'\d+|\D+')
      .allMatches(a.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  final rb = RegExp(r'\d+|\D+')
      .allMatches(b.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final x = ra[i];
    final y = rb[i];
    final xd = x.isNotEmpty && x.codeUnitAt(0) >= 48 && x.codeUnitAt(0) <= 57;
    final yd = y.isNotEmpty && y.codeUnitAt(0) >= 48 && y.codeUnitAt(0) <= 57;
    final c = (xd && yd)
        ? (int.tryParse(x) ?? 0).compareTo(int.tryParse(y) ?? 0)
        : x.compareTo(y);
    if (c != 0) return c;
  }
  return ra.length.compareTo(rb.length);
}

String _baseNoExt(String name) =>
    name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

class RowState {
  final String name;
  List<String> names;
  bool valid;
  String title;
  String season;
  String episode;
  String epTitle;
  String year;
  String tags;

  RowState(this.name, this.valid, EpisodeInfo info,
      {List<String>? names, this.epTitle = '', this.year = '', this.tags = ''})
      : names = names ?? [name],
        title = info.title,
        season = info.season,
        episode = info.episode;
}

class DirCacheEntry {
  final List<FsItem> dirs;
  final List<FsItem> files;
  final List<RowState> rows;
  DirCacheEntry(this.dirs, this.files, this.rows);
}

class ScrapeMemory {
  final TmdbResult selected;
  final String season;
  final Map<String, String> episodes;
  ScrapeMemory(this.selected, this.season, this.episodes);
}

/// Port of AppState + loadDir + doLogin from MainActivity.kt.
/// ChangeNotifier: call [touch] after mutating row fields.
class AppState extends ChangeNotifier {
  final SharedPreferences prefs;

  Renamer? renamer;
  bool loggedIn = false;
  bool loading = false;
  String loadError = '';
  bool committing = false;
  String currentPath = '/';
  List<FsItem> directories = [];
  List<FsItem> files = [];
  List<RowState> rows = [];
  String user = '';
  bool openlistOk = false;
  final Map<String, DirCacheEntry> dirCache = {};
  RowState? editingRow;
  bool toolsOpen = false;
  Set<String> selected = {};
  bool batchOpen = false;

  String scrapeSource = 'auto';
  final Map<String, List<TmdbResult>> tmdbSearchCache = {};
  final Map<String, Map<String, String>> episodeCache = {};
  String tmdbApiKey = defaultTmdbKey;
  String delimiter = '.';
  bool useEpisodeTitle = true;
  String defaultSeason = '1';
  String epStart = '1';
  bool darkTheme = false;

  String mediaType = 'tv';
  final Map<String, String> dirMediaType = {};

  String tmdbKeyword = '';
  String tmdbSeason = '1';
  List<TmdbResult> tmdbResults = [];
  TmdbResult? tmdbSelected;
  Map<String, String> tmdbEpisodes = {};
  bool tmdbSearching = false;
  bool tmdbFetching = false;
  List<String> mediaParams = [];

  int commitTotal = 0;
  int commitDoneCount = 0;
  List<String> commitFailedNames = [];
  bool commitFinished = false;

  final Map<String, ScrapeMemory> dirScrape = {};
  final Map<String, double> scrollMemory = {};

  AppState(this.prefs) {
    scrapeSource = prefs.getString('scrape_source') ?? 'auto';
    tmdbApiKey = prefs.getString('tmdb_api_key') ?? defaultTmdbKey;
    delimiter = prefs.getString('delimiter') ?? '.';
    useEpisodeTitle = prefs.getBool('use_episode_title') ?? true;
    defaultSeason = prefs.getString('default_season') ?? '1';
    epStart = prefs.getString('default_episode_start') ?? '1';
    darkTheme = (prefs.getString('theme') ?? 'light') == 'dark';
    mediaType = prefs.getString('media_type') ?? 'tv';
    tmdbSeason = defaultSeason;
  }

  void touch() => notifyListeners();

  void saveSetting() {
    prefs.setString('media_type', mediaType);
    prefs.setString('scrape_source', scrapeSource);
    prefs.setString('tmdb_api_key', tmdbApiKey);
    prefs.setString('delimiter', delimiter);
    prefs.setBool('use_episode_title', useEpisodeTitle);
    prefs.setString('default_season', defaultSeason);
    prefs.setString('default_episode_start', epStart);
    prefs.setString('theme', darkTheme ? 'dark' : 'light');
  }

  void saveScrape() {
    final sel = tmdbSelected;
    if (sel != null) {
      dirScrape[currentPath] =
          ScrapeMemory(sel, tmdbSeason, Map.of(tmdbEpisodes));
    }
    dirMediaType[currentPath] = mediaType;
  }

  void restoreScrape() {
    final mt = dirMediaType[currentPath];
    if (mt != null) mediaType = mt;
    final mem = dirScrape[currentPath];
    if (mem != null) {
      tmdbSelected = mem.selected;
      tmdbSeason = mem.season;
      tmdbEpisodes = Map.of(mem.episodes);
      fillFromSelection();
    }
  }

  String previewName(RowState r) {
    final d = delimiter.isEmpty ? '.' : delimiter;
    final title = r.title.isEmpty ? 'UNKNOWN' : r.title;
    final ext =
        r.name.contains('.') ? r.name.substring(r.name.lastIndexOf('.')) : '';
    if (mediaType == 'movie') {
      var name = title;
      if (r.year.trim().isNotEmpty) name += ' (${r.year.trim()})';
      if (r.tags.trim().isNotEmpty) {
        final parts = r.tags
            .split(RegExp(r'[,，;；|]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) name += d + parts.join(d);
      }
      return name + ext;
    }
    var name = '$title${d}S${pad2(r.season)}E${pad2(r.episode)}';
    if (useEpisodeTitle && r.epTitle.trim().isNotEmpty) {
      name += d + r.epTitle.trim();
    }
    if (r.tags.trim().isNotEmpty) {
      final parts = r.tags
          .split(RegExp(r'[,，;；|]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) name += d + parts.join(d);
    }
    return name + ext;
  }

  String previewBase(RowState r) {
    final full = previewName(r);
    return full.contains('.')
        ? full.substring(0, full.lastIndexOf('.'))
        : full;
  }

  int get renameableCount =>
      rows.where((r) => previewName(r) != r.name).length;

  void syncEpisodes() {
    if (mediaType == 'movie') return;
    final bcount = <String, int>{};
    for (final r in rows) {
      final b = _baseNoExt(r.name).toLowerCase();
      bcount[b] = (bcount[b] ?? 0) + 1;
    }
    final groups = <String, List<int>>{};
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final b = _baseNoExt(r.name).toLowerCase();
      final key = (bcount[b] ?? 0) > 1
          ? 'b$b'
          : (() {
              final s = r.season.padLeft(2, '0');
              final e = r.episode.padLeft(2, '0');
              if (s != '00' && e != '00' && s.isNotEmpty && e.isNotEmpty) {
                return 's${s}e$e';
              }
              return 'b$b';
            })();
      (groups[key] ??= []).add(i);
    }
    for (final g in groups.values) {
      if (g.length < 2) continue;
      final anchor = rows[g[0]];
      RowState? titled;
      for (final i in g) {
        if (rows[i].epTitle.trim().isNotEmpty) {
          titled = rows[i];
          break;
        }
      }
      for (final i in g) {
        final r = rows[i];
        r.title = anchor.title;
        r.season = anchor.season;
        r.episode = anchor.episode;
        r.tags = anchor.tags;
        if (titled != null && !identical(titled, r)) {
          r.epTitle = titled.epTitle;
        }
      }
    }
  }

  void applyEpisodeNumbers() {
    if (rows.isEmpty) return;
    final season = tmdbSeason.isEmpty ? '1' : tmdbSeason;
    var ep = int.tryParse(epStart) ?? 1;
    final groups = <String>[];
    final seen = <String>{};
    for (final r in rows) {
      final key = _baseNoExt(r.name).toLowerCase();
      if (seen.add(key)) groups.add(key);
    }
    for (final key in groups) {
      for (final r in rows) {
        if (_baseNoExt(r.name).toLowerCase() == key) {
          r.season = season;
          r.episode = ep.toString();
        }
      }
      ep++;
    }
    syncEpisodes();
  }

  void fillFromSelection() {
    final sel = tmdbSelected;
    if (sel == null) return;
    if (mediaType == 'movie') {
      for (final r in rows) {
        r.title = sel.name;
        r.year = sel.year;
      }
      syncEpisodes();
      return;
    }
    var n = 0;
    for (final r in rows) {
      r.title = sel.name;
      if (r.season.isEmpty) r.season = tmdbSeason.isEmpty ? '1' : tmdbSeason;
      final ep = int.tryParse(r.episode) ??
          ((int.tryParse(epStart) ?? 1) + n);
      r.episode = ep.toString();
      final t = tmdbEpisodes[ep.toString()];
      if (useEpisodeTitle && t != null) r.epTitle = t.trim();
      n++;
    }
    syncEpisodes();
  }

  void applyTags() {
    final joined = mediaParams.join(',');
    for (final r in rows) {
      r.tags = joined;
    }
    syncEpisodes();
  }

  void setMediaType(String t) {
    mediaType = t;
    dirMediaType[currentPath] = t;
    tmdbSelected = null;
    tmdbEpisodes = {};
    saveSetting();
    notifyListeners();
  }

  // ---------- login ----------

  static String normalizeBase(String base) {
    var b = base.trim();
    if (b.isEmpty) b = 'http://127.0.0.1:5244';
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      final host = b.split(RegExp(r'[/:]'))[0].toLowerCase();
      final useHttp = host == '127.0.0.1' ||
          host == 'localhost' ||
          host.endsWith('.internal') ||
          RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
      b = (useHttp ? 'http://' : 'https://') + b;
    }
    return b;
  }

  String _tokenKey(String username, String base) => 'token_$username@$base';

  Future<bool> relogin() async {
    final old = renamer;
    if (old == null) return false;
    try {
      final r = Renamer(old.baseUrlRaw, old.username, old.password);
      r.token = prefs.getString(_tokenKey(old.username, old.baseUrl));
      final ok = await r.login();
      if (ok) {
        if (r.token != null) {
          prefs.setString(_tokenKey(old.username, old.baseUrl), r.token!);
        }
        renamer = r;
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Returns null on success, otherwise a plain-language error message.
  Future<String?> doLogin(String base, String user, String pass) async {
    try {
      final b = normalizeBase(base);
      final r = Renamer(b, user, pass);
      r.token = prefs.getString(_tokenKey(user, r.baseUrl));
      final hasToken = r.token != null;
      if ((hasToken && await r.validateCurrentUser()) || await r.login()) {
        if (r.token != null) {
          prefs.setString(_tokenKey(user, r.baseUrl), r.token!);
        }
        renamer = r;
        this.user = user;
        openlistOk = true;
        loggedIn = true;
        prefs.setString('base_url', b);
        prefs.setString('username', user);
        prefs.setString('password', pass);
        notifyListeners();
        return null;
      }
      return '登录失败，请检查账号密码';
    } catch (e) {
      return _friendlyError(e);
    }
  }

  static String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') ||
        msg.contains('Connection refused') ||
        msg.contains('Connection timed out') ||
        msg.contains('Failed host lookup')) {
      return '连不上服务器，请检查地址和网络';
    }
    if (msg.contains('TimeoutException')) return '连接超时，服务器响应太慢';
    if (msg.startsWith('Exception: ')) return msg.substring('Exception: '.length);
    return msg.isEmpty ? '网络错误' : msg;
  }

  // ---------- directory loading ----------

  Future<void> loadDir({bool force = false}) async {
    final r = renamer;
    if (r == null) return;
    if (!force) {
      final cached = dirCache[currentPath];
      if (cached != null) {
        directories = cached.dirs;
        files = cached.files;
        rows = cached.rows;
        openlistOk = true;
        loadError = '';
        loading = false;
        if (dirMediaType[currentPath] == null) {
          final seRe =
              RegExp(r'S\d{1,2}[\s._\-]*E\d{1,3}', caseSensitive: false);
          mediaType =
              files.any((f) => seRe.hasMatch(f.name)) ? 'tv' : 'movie';
        }
        restoreScrape();
        notifyListeners();
        return;
      }
    }
    loading = true;
    loadError = '';
    notifyListeners();
    try {
      List<FsItem>? items;
      try {
        items = await r.listContents(currentPath);
      } catch (e) {
        // Only an auth-looking failure earns a re-login + retry; a slow or
        // unreachable server should fail fast instead of stacking round-trips.
        final msg = e.toString().toLowerCase();
        final authLike = msg.contains('token') ||
            msg.contains('401') ||
            msg.contains('unauthorized') ||
            msg.contains('登录') ||
            msg.contains('invalid');
        if (authLike && await relogin()) {
          final current = renamer;
          if (current != null) {
            items = await current.listContents(currentPath);
          }
        } else {
          rethrow;
        }
      }
      final list = items!;
      directories = list.where((e) => e.isDir).toList()
        ..sort((x, y) => natCmp(x.name, y.name));
      files = list.where((e) => !e.isDir).toList()
        ..sort((x, y) => natCmp(x.name, y.name));

      int extPri(String name) {
        final e = name.contains('.')
            ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
            : '';
        switch (e) {
          case 'mp4':
          case 'mkv':
          case 'avi':
          case 'ts':
          case 'mov':
          case 'webm':
          case 'flv':
          case 'wmv':
          case 'm4v':
          case 'mpg':
          case 'mpeg':
            return 0;
          case 'srt':
          case 'ass':
          case 'ssa':
          case 'vtt':
            return 1;
          default:
            return 2;
        }
      }

      // Group by parsed season/episode, not by filename: a subtitle and its
      // video often carry different release tags, but they are the same
      // episode.
      final seRe = RegExp(r'S\d{1,2}[\s._\-]*E\d{1,3}', caseSensitive: false);
      final parsed = files
          .map((f) => (f, renamer!.extractEpisodeInfo(f.name)))
          .toList();
      final groups = <String, List<(FsItem, EpisodeInfo)>>{};
      for (final p in parsed) {
        final f = p.$1;
        final info = p.$2;
        final sn = int.tryParse(info.season);
        final ep = int.tryParse(info.episode);
        final key = (seRe.hasMatch(f.name) && sn != null && ep != null)
            ? 'se_${sn}_$ep'
            : 'base_${_baseNoExt(f.name).toLowerCase()}';
        (groups[key] ??= []).add(p);
      }
      rows = groups.values.map((g) {
        final sorted = [...g]
          ..sort((a, b) {
            final c = extPri(a.$1.name).compareTo(extPri(b.$1.name));
            if (c != 0) return c;
            return natCmp(a.$1.name, b.$1.name);
          });
        final main = sorted.first.$1;
        final info = sorted.first.$2;
        final row = RowState(main.name, true, info);
        row.names = sorted.map((e) => e.$1.name).toList();
        row.tags = detectMediaParams(main.name).join(',');
        return row;
      }).toList()
        ..sort((a, b) {
          final sa = int.tryParse(a.season) ?? 999;
          final sb = int.tryParse(b.season) ?? 999;
          final ea = int.tryParse(a.episode) ?? 99999;
          final eb = int.tryParse(b.episode) ?? 99999;
          if (sa != sb) return sa.compareTo(sb);
          if (ea != eb) return ea.compareTo(eb);
          return natCmp(a.name, b.name);
        });
      openlistOk = true;
      selected = {};
      dirCache[currentPath] = DirCacheEntry(directories, files, rows);
      if (dirMediaType[currentPath] == null) {
        mediaType =
            files.any((f) => seRe.hasMatch(f.name)) ? 'tv' : 'movie';
      }
      restoreScrape();
    } catch (e) {
      openlistOk = false;
      loadError = _friendlyError(e);
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ---------- TMDB / TVmaze search ----------

  /// Panel search: cache + exact-title boost. Throws on failure.
  Future<List<TmdbResult>> doSearch() async {
    final kw = tmdbKeyword.trim();
    final cacheKey = '${mediaType}_$kw';
    final cached = tmdbSearchCache[cacheKey];
    if (cached != null) {
      tmdbResults = cached;
      notifyListeners();
      return cached;
    }
    final r = renamer!;
    List<TmdbResult> raw;
    if (mediaType == 'movie') {
      // TVmaze has no movies: movies always go through TMDB.
      raw = (await r.tmdbSearchMovie(kw, tmdbApiKey.trim())).$1;
    } else {
      switch (scrapeSource) {
        case 'tvmaze':
          raw = await tvmazeSearch(kw);
          break;
        case 'tmdb':
          raw = (await r.tmdbSearch(kw, tmdbApiKey.trim())).$1;
          break;
        default:
          try {
            raw = (await r.tmdbSearch(kw, tmdbApiKey.trim())).$1;
          } catch (_) {
            raw = await tvmazeSearch(kw);
          }
      }
    }
    // TMDB ranks by popularity, so an unreleased sequel can outrank the
    // exact title: exact matches first.
    final results = [...raw]
      ..sort((a, b) =>
          (a.name.trim() == kw ? 0 : 1).compareTo(b.name.trim() == kw ? 0 : 1));
    tmdbSearchCache[cacheKey] = results;
    tmdbResults = results;
    notifyListeners();
    return results;
  }

  /// Fetch episode titles for the selected show/season (cached).
  /// Throws on failure.
  Future<void> fetchSelectedEpisodes() async {
    final res = tmdbSelected;
    if (res == null) return;
    if (mediaType == 'movie') {
      fillFromSelection();
      saveScrape();
      notifyListeners();
      return;
    }
    tmdbFetching = true;
    fillFromSelection();
    notifyListeners();
    try {
      final season = int.tryParse(tmdbSeason) ?? 1;
      final key = '${scrapeSource}_${res.id}_$season';
      final cached = episodeCache[key];
      Map<String, String> eps;
      if (cached != null) {
        eps = cached;
      } else {
        final r = renamer!;
        switch (scrapeSource) {
          case 'tvmaze':
            eps = await tvmazeEpisodes(res.id, season);
            break;
          case 'tmdb':
            eps = (await r.tmdbFetch(res.id, season, tmdbApiKey.trim())).$1;
            break;
          default:
            try {
              eps =
                  (await r.tmdbFetch(res.id, season, tmdbApiKey.trim())).$1;
            } catch (_) {
              final found = await tvmazeSearch(res.name);
              final alt = found.isEmpty ? null : found.first;
              eps = alt != null
                  ? await tvmazeEpisodes(alt.id, season)
                  : <String, String>{};
            }
        }
        episodeCache[key] = eps;
      }
      tmdbEpisodes = eps;
      fillFromSelection();
      saveScrape();
    } finally {
      tmdbFetching = false;
      notifyListeners();
    }
  }

  /// Single-file sheet search: never touches the panel selection.
  Future<List<TmdbResult>> searchSingle(String kw) async {
    final r = renamer!;
    List<TmdbResult> raw;
    if (mediaType == 'movie') {
      raw = (await r.tmdbSearchMovie(kw, tmdbApiKey.trim())).$1;
    } else {
      switch (scrapeSource) {
        case 'tvmaze':
          raw = await tvmazeSearch(kw);
          break;
        case 'tmdb':
          raw = (await r.tmdbSearch(kw, tmdbApiKey.trim())).$1;
          break;
        default:
          try {
            raw = (await r.tmdbSearch(kw, tmdbApiKey.trim())).$1;
          } catch (_) {
            raw = await tvmazeSearch(kw);
          }
      }
    }
    return [...raw]
      ..sort((a, b) =>
          (a.name.trim() == kw ? 0 : 1).compareTo(b.name.trim() == kw ? 0 : 1));
  }

  /// Episode titles for a single-file pick (no cache pollution of the panel).
  Future<Map<String, String>> fetchEpisodesFor(
      TmdbResult res, int season) async {
    final r = renamer!;
    switch (scrapeSource) {
      case 'tvmaze':
        return tvmazeEpisodes(res.id, season);
      case 'tmdb':
        return (await r.tmdbFetch(res.id, season, tmdbApiKey.trim())).$1;
      default:
        try {
          return (await r.tmdbFetch(res.id, season, tmdbApiKey.trim())).$1;
        } catch (_) {
          final found = await tvmazeSearch(res.name);
          final alt = found.isEmpty ? null : found.first;
          if (alt != null) return tvmazeEpisodes(alt.id, season);
          return <String, String>{};
        }
    }
  }

  // ---------- rename ----------

  String _fullPath(String name) =>
      currentPath == '/' ? '/$name' : '$currentPath/$name';

  /// Runs the rename of [changes] (rows), updating commit progress fields.
  /// Returns the number of successfully renamed files.
  Future<int> commitRename(List<RowState> changes) async {
    committing = true;
    commitFinished = false;
    commitFailedNames = [];
    commitDoneCount = 0;
    var total = 0;
    for (final r in changes) {
      for (final fname in r.names) {
        final ext = fname.contains('.')
            ? fname.substring(fname.lastIndexOf('.'))
            : '';
        if (previewBase(r) + ext != fname) total++;
      }
    }
    commitTotal = total;
    notifyListeners();
    var okCount = 0;
    try {
      try {
        final alive = await renamer!.validateCurrentUser();
        if (!alive) await relogin();
      } catch (_) {
        await relogin();
      }
      for (final r in changes) {
        final base = previewBase(r);
        for (final fname in r.names) {
          final ext = fname.contains('.')
              ? fname.substring(fname.lastIndexOf('.'))
              : '';
          final newName = base + ext;
          if (newName == fname) continue;
          try {
            final ok =
                await renamer!.renameSingle(_fullPath(fname), newName);
            if (ok) {
              okCount++;
            } else {
              commitFailedNames = [...commitFailedNames, fname];
            }
          } catch (_) {
            commitFailedNames = [...commitFailedNames, fname];
          }
          commitDoneCount++;
          notifyListeners();
        }
      }
    } finally {
      committing = false;
      commitFinished = true;
      notifyListeners();
    }
    if (okCount > 0) {
      await loadDir(force: true);
    }
    return okCount;
  }

  Future<bool> renameDirectory(FsItem dir, String newName) async {
    try {
      final ok = await renamer!.renameSingle(dir.path, newName);
      if (ok) {
        dirCache.clear();
        await loadDir(force: true);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  void logout() {
    prefs.remove('password');
    renamer = null;
    loggedIn = false;
    rows = [];
    notifyListeners();
  }
}
