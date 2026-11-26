import 'dart:convert';

import 'package:http/http.dart' as http;

/// Port of Engine.kt (OpenList episode renamer, native Android v3.4).

const String defaultTmdbKey = '08a6bef260044f70c150251c79f2e476';

const String _androidUa =
    'Mozilla/5.0 (Linux; Android 14) OpenListRenamer/1.0';
const String _chromeUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Map<String, String> _tmdbHeaders() => {
      'User-Agent': _chromeUa,
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };

String _take(String s, int n) => s.length <= n ? s : s.substring(0, n);

int _optInt(Map<String, dynamic> obj, String key) {
  final v = obj[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String _optString(Map<String, dynamic> obj, String key) {
  final v = obj[key];
  if (v == null) return '';
  return v.toString();
}

class Http {
  static Future<String> request(
    String method,
    String urlStr, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
    int timeoutMs = 30000,
  }) async {
    final uri = Uri.parse(urlStr);
    final h = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': _androidUa,
      ...headers,
    };
    late http.Response res;
    if (method == 'POST') {
      res = await http
          .post(uri, headers: h, body: body == null ? null : jsonEncode(body))
          .timeout(Duration(milliseconds: timeoutMs));
    } else {
      res = await http
          .get(uri, headers: h)
          .timeout(Duration(milliseconds: timeoutMs));
    }
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${_take(text, 200)}');
    }
    return text;
  }

  static Future<String> getText(
    String urlStr, {
    Map<String, String> headers = const {},
    int timeoutMs = 15000,
  }) async {
    final res = await http
        .get(Uri.parse(urlStr), headers: headers)
        .timeout(Duration(milliseconds: timeoutMs));
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return text;
  }
}

String cleanSeriesName(String name) =>
    name.replaceAll(RegExp(r'\s*[（(][^（）()]*[）)]'), '').trim();

class FsItem {
  final String name;
  final bool isDir;
  final int size;
  final String path;
  const FsItem(this.name, this.isDir, this.size, this.path);
}

class EpisodeInfo {
  String title;
  String season;
  String episode;
  EpisodeInfo(this.title, this.season, this.episode);
}

class TmdbResult {
  final int id;
  final String name;
  final String overview;
  final String year;
  final String poster;
  const TmdbResult(this.id, this.name, this.overview, this.year, this.poster);
}

String _trimChars(String s, String chars) {
  final re = RegExp('^[$chars]+|[$chars]+\$');
  return s.replaceAll(re, '');
}

class Renamer {
  final String baseUrlRaw;
  final String username;
  final String password;
  late final String baseUrl;
  String? token;

  Renamer(this.baseUrlRaw, this.username, this.password) {
    baseUrl = baseUrlRaw.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Future<bool> login() async {
    final res = await Http.request(
      'POST',
      '$baseUrl/api/auth/login',
      body: {'username': username, 'password': password},
      timeoutMs: 15000,
    );
    final obj = jsonDecode(res) as Map<String, dynamic>;
    if (_optInt(obj, 'code') == 200) {
      final data = obj['data'] as Map<String, dynamic>?;
      final t = data == null ? '' : _optString(data, 'token');
      token = t.isNotEmpty ? t : null;
      return token != null;
    }
    return false;
  }

  Future<bool> validateCurrentUser() async {
    final t = token;
    if (t == null) return false;
    try {
      final obj = jsonDecode(await Http.request(
        'GET',
        '$baseUrl/api/me',
        headers: {'Authorization': t},
        timeoutMs: 8000,
      )) as Map<String, dynamic>;
      if (_optInt(obj, 'code') == 200) {
        final data = obj['data'] as Map<String, dynamic>?;
        if (data == null) return true;
        final u = _optString(data, 'username');
        return u.isEmpty || u == username;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _authHeaders() {
    final t = token;
    if (t == null) throw Exception('未登录');
    return {'Authorization': t};
  }

  Future<List<FsItem>> listContents(String path) async {
    final obj = jsonDecode(await Http.request(
      'POST',
      '$baseUrl/api/fs/list',
      body: {
        'path': path,
        'password': '',
        'page': 1,
        'per_page': 0,
        'refresh': false,
      },
      headers: _authHeaders(),
    )) as Map<String, dynamic>;
    if (_optInt(obj, 'code') != 200) {
      throw Exception(_optString(obj, 'message').isEmpty
          ? '获取目录失败'
          : _optString(obj, 'message'));
    }
    final data = obj['data'] as Map<String, dynamic>?;
    final content = (data?['content'] as List?) ?? const [];
    final base = path.replaceAll(RegExp(r'/+$'), '');
    final out = <FsItem>[];
    for (final item in content) {
      final it = item as Map<String, dynamic>;
      final name = _optString(it, 'name');
      out.add(FsItem(
        name,
        it['is_dir'] == true,
        _optInt(it, 'size'),
        base.isEmpty ? '/$name' : '$base/$name',
      ));
    }
    return out;
  }

  Future<bool> renameSingle(String path, String newName) async {
    final obj = jsonDecode(await Http.request(
      'POST',
      '$baseUrl/api/fs/rename',
      body: {'path': path, 'name': newName},
      headers: _authHeaders(),
    )) as Map<String, dynamic>;
    return _optInt(obj, 'code') == 200;
  }

  EpisodeInfo extractEpisodeInfo(String filename) {
    // Strict SxxEyy first: loose numeric patterns mistake years (1988, 2015)
    // for season/episode.
    final strict = RegExp(
        r'^(.+?)[\s._\-]*[Ss](\d{1,2})[\s._\-]*[Ee](\d{1,3})(?:\D|$)');
    final sm = strict.firstMatch(filename);
    if (sm != null) {
      var t = _trimChars(sm.group(1)!, ' ._-');
      // Drop a trailing year wedged between the title and SxxEyy
      // ("Reply 1988 2015" -> "Reply 1988").
      final stripped = _trimChars(
          t.replaceAll(RegExp(r'[\s._\-]+(19|20)\d{2}$'), ''), ' ._-');
      if (stripped.isNotEmpty) t = stripped;
      if (t.isNotEmpty) {
        return EpisodeInfo(t, sm.group(2)!, sm.group(3)!);
      }
    }
    final patterns = [
      RegExp(r'(.+?)[\s._-]*S?(\d+)[\s._-]*E?(\d+)', caseSensitive: false),
      RegExp(r'(.+?)[\s._-]*(\d+)[\s._-]*(\d{2})', caseSensitive: false),
      RegExp(r'(.+?)[\s._-]*EP?[\s._-]*(\d+)', caseSensitive: false),
      RegExp(r'(.+?)[\s._-]*(\d+)[\s._-]*of[\s._-]*\d+', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(filename);
      if (m == null) continue;
      final g1 = m.group(1) ?? '';
      final g2 = m.group(2) ?? '';
      final g3 = m.groupCount >= 3 ? (m.group(3) ?? '') : '';
      if (m.groupCount >= 2) {
        // Kotlin quirk: 2-group patterns get season == episode == group 2.
        return EpisodeInfo(_trimChars(g1, ' ._-'), g2,
            m.groupCount > 2 ? g3 : g2);
      }
    }
    final name = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;
    return EpisodeInfo(name, '1', '1');
  }

  // ---------- TMDB (API first, scrape fallback) ----------

  Future<List<TmdbResult>> tmdbApiSearch(String keyword, String apiKey) async {
    final q = Uri.encodeQueryComponent(keyword);
    final obj = jsonDecode(await Http.getText(
      'https://api.themoviedb.org/3/search/tv?api_key=$apiKey&query=$q&language=zh-CN',
      timeoutMs: 8000,
    )) as Map<String, dynamic>;
    final results = (obj['results'] as List?) ?? const [];
    final out = <TmdbResult>[];
    for (var i = 0; i < results.length && i < 10; i++) {
      final r = results[i] as Map<String, dynamic>;
      final posterPath = _optString(r, 'poster_path');
      out.add(TmdbResult(
        _optInt(r, 'id'),
        cleanSeriesName(_optString(r, 'name')),
        _take(_optString(r, 'overview'), 120),
        _take(_optString(r, 'first_air_date'), 4),
        posterPath.isNotEmpty && posterPath != 'null'
            ? 'https://image.tmdb.org/t/p/w185$posterPath'
            : '',
      ));
    }
    return out;
  }

  Future<Map<String, String>> tmdbApiSeason(
      int id, int season, String apiKey) async {
    final obj = jsonDecode(await Http.getText(
      'https://api.themoviedb.org/3/tv/$id/season/$season?api_key=$apiKey&language=zh-CN',
      timeoutMs: 8000,
    )) as Map<String, dynamic>;
    final eps = (obj['episodes'] as List?) ?? const [];
    final out = <String, String>{};
    for (final e in eps) {
      final ep = e as Map<String, dynamic>;
      final name = _optString(ep, 'name');
      if (name.isNotEmpty) {
        out[_optInt(ep, 'episode_number').toString()] = name;
      }
    }
    return out;
  }

  Future<List<TmdbResult>> tmdbScrapeSearch(String keyword) async {
    final q = Uri.encodeQueryComponent(keyword);
    final html = await Http.getText(
      'https://www.themoviedb.org/search/tv?query=$q&language=zh-CN',
      headers: _tmdbHeaders(),
    );
    final out = <TmdbResult>[];
    final seen = <String>{};
    final linkRe = RegExp(
      r'''href="/tv/(\d+)[^"]*"[^>]*>(?:(?!</a>).)*?<h2[^>]*>([^<]+)</h2>''',
      dotAll: true,
      caseSensitive: false,
    );
    for (final m in linkRe.allMatches(html)) {
      final id = m.group(1)!;
      if (seen.contains(id)) continue;
      seen.add(id);
      out.add(TmdbResult(
          int.parse(id), cleanSeriesName(m.group(2)!.trim()), '', '', ''));
      if (out.length >= 10) break;
    }
    if (out.isEmpty) {
      // Looser fallback: ids + titles from alt attributes.
      final altRe = RegExp(
        r'''href="/tv/(\d+)-[^"]*"[^>]*>\s*<img[^>]*alt="([^"]+)''',
        caseSensitive: false,
      );
      for (final m in altRe.allMatches(html)) {
        final id = m.group(1)!;
        if (seen.contains(id)) continue;
        seen.add(id);
        out.add(TmdbResult(
            int.parse(id), cleanSeriesName(m.group(2)!.trim()), '', '', ''));
        if (out.length >= 10) break;
      }
    }
    return out;
  }

  Future<Map<String, String>> tmdbScrapeSeason(int id, int season) async {
    final html = await Http.getText(
      'https://www.themoviedb.org/tv/$id/season/$season?language=zh-CN',
      headers: _tmdbHeaders(),
    );
    final out = <String, String>{};
    final re = RegExp(
      r'episode_number[^>]*>\s*(\d+)\s*<.*?episode_title[^>]*>.*?<a[^>]*>([^<]+)</a>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final m in re.allMatches(html)) {
      out[m.group(1)!] = m.group(2)!.trim();
    }
    return out;
  }

  Future<List<TmdbResult>> tmdbApiSearchMovie(
      String keyword, String apiKey) async {
    final q = Uri.encodeQueryComponent(keyword);
    final obj = jsonDecode(await Http.getText(
      'https://api.themoviedb.org/3/search/movie?api_key=$apiKey&query=$q&language=zh-CN',
      timeoutMs: 8000,
    )) as Map<String, dynamic>;
    final results = (obj['results'] as List?) ?? const [];
    final out = <TmdbResult>[];
    for (var i = 0; i < results.length && i < 10; i++) {
      final r = results[i] as Map<String, dynamic>;
      final posterPath = _optString(r, 'poster_path');
      out.add(TmdbResult(
        _optInt(r, 'id'),
        cleanSeriesName(_optString(r, 'title')),
        _take(_optString(r, 'overview'), 120),
        _take(_optString(r, 'release_date'), 4),
        posterPath.isNotEmpty && posterPath != 'null'
            ? 'https://image.tmdb.org/t/p/w185$posterPath'
            : '',
      ));
    }
    return out;
  }

  Future<(List<TmdbResult>, String)> tmdbSearchMovie(
      String keyword, String apiKey) async {
    if (apiKey.trim().isNotEmpty) {
      try {
        return (await tmdbApiSearchMovie(keyword, apiKey), 'api');
      } catch (_) {
        // fall through to scrape
      }
    }
    final q = Uri.encodeQueryComponent(keyword);
    final html = await Http.getText(
      'https://www.themoviedb.org/search/movie?query=$q&language=zh-CN',
      headers: _tmdbHeaders(),
    );
    final out = <TmdbResult>[];
    final seen = <String>{};
    final linkRe = RegExp(
      r'''href="/movie/(\d+)[^"]*"[^>]*>(?:(?!</a>).)*?<h2[^>]*>([^<]+)</h2>''',
      dotAll: true,
      caseSensitive: false,
    );
    for (final m in linkRe.allMatches(html)) {
      final id = m.group(1)!;
      if (seen.contains(id)) continue;
      seen.add(id);
      out.add(TmdbResult(
          int.parse(id), cleanSeriesName(m.group(2)!.trim()), '', '', ''));
      if (out.length >= 10) break;
    }
    return (out, 'scrape');
  }

  Future<(List<TmdbResult>, String)> tmdbSearch(
      String keyword, String apiKey) async {
    if (apiKey.trim().isNotEmpty) {
      try {
        return (await tmdbApiSearch(keyword, apiKey), 'api');
      } catch (_) {
        // fall through to scrape
      }
    }
    return (await tmdbScrapeSearch(keyword), 'scrape');
  }

  Future<(Map<String, String>, String)> tmdbFetch(
      int id, int season, String apiKey) async {
    if (apiKey.trim().isNotEmpty) {
      try {
        return (await tmdbApiSeason(id, season, apiKey), 'api');
      } catch (_) {
        // fall through to scrape
      }
    }
    return (await tmdbScrapeSeason(id, season), 'scrape');
  }
}

/// TVmaze: free, no API key, generous limits — the fast fallback when TMDB
/// is slow or 429s.
Future<List<TmdbResult>> tvmazeSearch(String keyword) async {
  final q = Uri.encodeQueryComponent(keyword);
  final arr = jsonDecode(await Http.getText(
    'https://api.tvmaze.com/search/shows?q=$q',
    timeoutMs: 8000,
  )) as List;
  final out = <TmdbResult>[];
  for (var i = 0; i < arr.length && i < 10; i++) {
    final item = arr[i] as Map<String, dynamic>;
    final show = (item['show'] as Map<String, dynamic>?) ?? {};
    final img = (show['image'] as Map<String, dynamic>?)?['medium'];
    final summary = _optString(show, 'summary')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
    out.add(TmdbResult(
      _optInt(show, 'id'),
      cleanSeriesName(_optString(show, 'name')),
      _take(summary, 120),
      _take(_optString(show, 'premiered'), 4),
      img is String ? img : '',
    ));
  }
  return out;
}

Future<Map<String, String>> tvmazeEpisodes(int id, int season) async {
  final arr = jsonDecode(await Http.getText(
    'https://api.tvmaze.com/shows/$id/episodes',
    timeoutMs: 8000,
  )) as List;
  final out = <String, String>{};
  for (final item in arr) {
    final e = item as Map<String, dynamic>;
    if (_optInt(e, 'season') == season) {
      final name = _optString(e, 'name');
      if (name.isNotEmpty) {
        out[_optInt(e, 'number').toString()] = name;
      }
    }
  }
  return out;
}

/// Detect media tags straight from the release filename: resolution, codec,
/// HDR, audio, language.
List<String> detectMediaParams(String filename) {
  final u = filename.toUpperCase();
  final out = <String>[];
  bool has(List<String> pats) => pats.any(u.contains);
  if (has(['2160P']) ||
      RegExp(r'(^|[\s._-])4K([\s._-]|$)').hasMatch(u)) {
    out.add('4K');
  } else if (has(['1080P'])) {
    out.add('1080p');
  } else if (has(['720P'])) {
    out.add('720p');
  } else if (has(['480P'])) {
    out.add('480p');
  }
  if (has(['HDR10+'])) {
    out.add('HDR10+');
  } else if (has(['HDR10'])) {
    out.add('HDR10');
  } else if (has(['DOLBY VISION']) ||
      RegExp(r'(^|[\s._-])DV([\s._-]|$)').hasMatch(u)) {
    out.add('DV');
  } else if (has(['HDR'])) {
    out.add('HDR');
  }
  if (has(['X265', 'HEVC', 'H.265', 'H265'])) {
    out.add('HEVC');
  } else if (has(['X264', 'H.264', 'H264', 'AVC'])) {
    out.add('H.264');
  } else if (has(['VP9'])) {
    out.add('VP9');
  } else if (has(['AV1'])) {
    out.add('AV1');
  }
  if (has(['DTS-HD', 'DTSHD'])) {
    out.add('DTS-HD');
  } else if (has(['TRUEHD'])) {
    out.add('TrueHD');
  } else if (has(['ATMOS'])) {
    out.add('Atmos');
  } else if (has(['DTS'])) {
    out.add('DTS');
  } else if (has(['EAC3', 'DD+', 'DDP'])) {
    out.add('DD+');
  } else if (has(['AC3'])) {
    out.add('AC3');
  } else if (has(['AAC'])) {
    out.add('AAC');
  } else if (has(['FLAC'])) {
    out.add('FLAC');
  }
  if (has(['中英', '中英字幕', '中英双字', '中英双语'])) {
    out.add('中英字幕');
  } else if (has(['中字', '简中', '繁中'])) {
    out.add('中字');
  } else if (has(['国语', '国配'])) {
    out.add('国语');
  } else if (has(['粤语'])) {
    out.add('粤语');
  }
  return out;
}
