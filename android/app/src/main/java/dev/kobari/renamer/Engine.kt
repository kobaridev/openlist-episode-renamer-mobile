package dev.kobari.renamer

import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** Port of core.py (InteractiveEpisodeRenamer) + TMDB parts of server.py. */
object Http {
    fun request(method: String, urlStr: String, body: JSONObject? = null,
                headers: Map<String, String> = emptyMap(), timeoutMs: Int = 30000): String {
        val conn = URL(urlStr).openConnection() as HttpURLConnection
        conn.requestMethod = method
        conn.connectTimeout = timeoutMs
        conn.readTimeout = timeoutMs
        conn.setRequestProperty("Content-Type", "application/json")
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) OpenListRenamer/1.0")
        headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }
        if (body != null) {
            conn.doOutput = true
            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(body.toString()) }
        }
        val code = conn.responseCode
        val stream = if (code in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.let { BufferedReader(InputStreamReader(it, Charsets.UTF_8)).readText() } ?: ""
        if (code !in 200..299) throw RuntimeException("HTTP $code: ${text.take(200)}")
        return text
    }
    fun getText(urlStr: String, headers: Map<String, String> = emptyMap(), timeoutMs: Int = 15000): String {
        val conn = URL(urlStr).openConnection() as HttpURLConnection
        conn.requestMethod = "GET"; conn.connectTimeout = timeoutMs; conn.readTimeout = timeoutMs
        headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }
        val code = conn.responseCode
        val stream = if (code in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.let { BufferedReader(InputStreamReader(it, Charsets.UTF_8)).readText() } ?: ""
        if (code !in 200..299) throw RuntimeException("HTTP $code")
        return text
    }
}

fun cleanSeriesName(name: String): String =
    name.replace(Regex("""\s*[（(][^（）()]*[）)]"""), "").trim()

data class FsItem(val name: String, val isDir: Boolean, val size: Long, val path: String)
data class EpisodeInfo(var title: String, var season: String, var episode: String)
data class TmdbResult(val id: Int, val name: String, val overview: String, val year: String, val poster: String)

class Renamer(val baseUrlRaw: String, val username: String, val password: String) {
    val baseUrl: String = baseUrlRaw.trim().trimEnd('/')
    var token: String? = null

    fun login(): Boolean {
        val res = Http.request("POST", "$baseUrl/api/auth/login",
            JSONObject().put("username", username).put("password", password), timeoutMs = 15000)
        val obj = JSONObject(res)
        if (obj.optInt("code") == 200) {
            token = obj.optJSONObject("data")?.optString("token")?.takeIf { it.isNotEmpty() }
            return token != null
        }
        return false
    }

    fun validateCurrentUser(): Boolean {
        val t = token ?: return false
        return try {
            val obj = JSONObject(Http.request("GET", "$baseUrl/api/me", null,
                mapOf("Authorization" to t), timeoutMs = 8000))
            if (obj.optInt("code") == 200) {
                val data = obj.optJSONObject("data") ?: return true
                val u = data.optString("username", "")
                u.isEmpty() || u == username
            } else false
        } catch (e: Exception) { false }
    }

    private fun authHeaders(): Map<String, String> =
        mapOf("Authorization" to (token ?: throw RuntimeException("未登录")))

    fun listContents(path: String): List<FsItem> {
        val obj = JSONObject(Http.request("POST", "$baseUrl/api/fs/list",
            JSONObject().put("path", path).put("password", "").put("page", 1).put("per_page", 0).put("refresh", false), authHeaders()))
        if (obj.optInt("code") != 200) throw RuntimeException(obj.optString("message", "获取目录失败"))
        val content: JSONArray = obj.optJSONObject("data")?.optJSONArray("content") ?: JSONArray()
        val base = path.trimEnd('/')
        val out = mutableListOf<FsItem>()
        for (i in 0 until content.length()) {
            val it = content.optJSONObject(i) ?: continue
            val name = it.optString("name")
            out.add(FsItem(name, it.optBoolean("is_dir"), it.optLong("size"),
                if (base.isEmpty()) "/$name" else "$base/$name"))
        }
        return out
    }

    fun renameSingle(path: String, newName: String): Boolean {
        val obj = JSONObject(Http.request("POST", "$baseUrl/api/fs/rename",
            JSONObject().put("path", path).put("name", newName), authHeaders()))
        return obj.optInt("code") == 200
    }

    fun extractEpisodeInfo(filename: String): EpisodeInfo {
        // Strict SxxEyy first: loose numeric patterns mistake years (1988, 2015) for season/episode.
        val strict = Regex("""^(.+?)[\s._\-]*[Ss](\d{1,2})[\s._\-]*[Ee](\d{1,3})(?:\D|$)""")
        strict.find(filename)?.let { m ->
            var t = m.groupValues[1].trim(' ', '.', '_', '-')
            // Drop a trailing year wedged between the title and SxxEyy ("Reply 1988 2015" -> "Reply 1988").
            val stripped = t.replace(Regex("""[\s._\-]+(19|20)\d{2}$"""), "").trim(' ', '.', '_', '-')
            if (stripped.isNotEmpty()) t = stripped
            if (t.isNotEmpty()) return EpisodeInfo(t, m.groupValues[2], m.groupValues[3])
        }
        val patterns = listOf(
            Regex("""(.+?)[\s._-]*S?(\d+)[\s._-]*E?(\d+)""", RegexOption.IGNORE_CASE),
            Regex("""(.+?)[\s._-]*(\d+)[\s._-]*(\d{2})""", RegexOption.IGNORE_CASE),
            Regex("""(.+?)[\s._-]*EP?[\s._-]*(\d+)""", RegexOption.IGNORE_CASE),
            Regex("""(.+?)[\s._-]*(\d+)[\s._-]*of[\s._-]*\d+""", RegexOption.IGNORE_CASE)
        )
        for (p in patterns) {
            val m = p.find(filename) ?: continue
            val g = m.groupValues
            if (g.size >= 3) {
                return EpisodeInfo(g[1].trim(' ', '.', '_', '-'),
                    g[2], if (g.size > 3) g[3] else g[2])
            } else if (g.size >= 2) {
                return EpisodeInfo(g[1].trim(' ', '.', '_', '-'), "1", g[1])
            }
        }
        val name = filename.substringBeforeLast('.', filename)
        return EpisodeInfo(name, "1", "1")
    }

    // ---------- TMDB (API first, scrape fallback) ----------
    fun tmdbApiSearch(keyword: String, apiKey: String): List<TmdbResult> {
        val q = URLEncoder.encode(keyword, "UTF-8")
        val obj = JSONObject(Http.getText(
            "https://api.themoviedb.org/3/search/tv?api_key=$apiKey&query=$q&language=zh-CN", timeoutMs = 8000))
        val results = obj.optJSONArray("results") ?: JSONArray()
        val out = mutableListOf<TmdbResult>()
        for (i in 0 until minOf(results.length(), 10)) {
            val r = results.optJSONObject(i) ?: continue
            val posterPath = r.optString("poster_path", "")
            out.add(TmdbResult(
                r.optInt("id"), cleanSeriesName(r.optString("name")),
                r.optString("overview").take(120),
                r.optString("first_air_date").take(4),
                if (posterPath.isNotEmpty() && posterPath != "null") "https://image.tmdb.org/t/p/w185$posterPath" else ""))
        }
        return out
    }

    fun tmdbApiSeason(id: Int, season: Int, apiKey: String): Map<String, String> {
        val obj = JSONObject(Http.getText(
            "https://api.themoviedb.org/3/tv/$id/season/$season?api_key=$apiKey&language=zh-CN", timeoutMs = 8000))
        val eps = obj.optJSONArray("episodes") ?: JSONArray()
        val out = mutableMapOf<String, String>()
        for (i in 0 until eps.length()) {
            val e = eps.optJSONObject(i) ?: continue
            val name = e.optString("name")
            if (name.isNotEmpty()) out[e.optInt("episode_number").toString()] = name
        }
        return out
    }

    fun tmdbScrapeSearch(keyword: String): List<TmdbResult> {
        val q = URLEncoder.encode(keyword, "UTF-8")
        val html = Http.getText("https://www.themoviedb.org/search/tv?query=$q&language=zh-CN", tmdbHeaders())
        val out = mutableListOf<TmdbResult>(); val seen = mutableSetOf<String>()
        val linkRe = Regex("""href="/tv/(\d+)[^"]*"[^>]*>(?:(?!</a>).)*?<h2[^>]*>([^<]+)</h2>""", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
        for (m in linkRe.findAll(html)) {
            val id = m.groupValues[1]
            if (id in seen) continue
            seen.add(id)
            out.add(TmdbResult(id.toInt(), cleanSeriesName(m.groupValues[2].trim()), "", "", ""))
            if (out.size >= 10) break
        }
        if (out.isEmpty()) { // looser fallback: ids + titles from alt attributes
            val altRe = Regex("""href="/tv/(\d+)-[^"]*"[^>]*>\s*<img[^>]*alt="([^"]+)""", RegexOption.IGNORE_CASE)
            for (m in altRe.findAll(html)) {
                val id = m.groupValues[1]; if (id in seen) continue; seen.add(id)
                out.add(TmdbResult(id.toInt(), cleanSeriesName(m.groupValues[2].trim()), "", "", ""))
                if (out.size >= 10) break
            }
        }
        return out
    }

    fun tmdbScrapeSeason(id: Int, season: Int): Map<String, String> {
        val html = Http.getText("https://www.themoviedb.org/tv/$id/season/$season?language=zh-CN", tmdbHeaders())
        val out = mutableMapOf<String, String>()
        val re = Regex("""episode_number[^>]*>\s*(\d+)\s*<.*?episode_title[^>]*>.*?<a[^>]*>([^<]+)</a>""",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
        for (m in re.findAll(html)) out[m.groupValues[1]] = m.groupValues[2].trim()
        return out
    }

    fun tmdbApiSearchMovie(keyword: String, apiKey: String): List<TmdbResult> {
        val q = URLEncoder.encode(keyword, "UTF-8")
        val obj = JSONObject(Http.getText(
            "https://api.themoviedb.org/3/search/movie?api_key=$apiKey&query=$q&language=zh-CN", timeoutMs = 8000))
        val results = obj.optJSONArray("results") ?: JSONArray()
        val out = mutableListOf<TmdbResult>()
        for (i in 0 until minOf(results.length(), 10)) {
            val r = results.optJSONObject(i) ?: continue
            val posterPath = r.optString("poster_path", "")
            out.add(TmdbResult(
                r.optInt("id"), cleanSeriesName(r.optString("title")),
                r.optString("overview").take(120),
                r.optString("release_date").take(4),
                if (posterPath.isNotEmpty() && posterPath != "null") "https://image.tmdb.org/t/p/w185$posterPath" else ""))
        }
        return out
    }

    fun tmdbSearchMovie(keyword: String, apiKey: String): Pair<List<TmdbResult>, String> {
        if (apiKey.isNotBlank()) {
            try { return tmdbApiSearchMovie(keyword, apiKey) to "api" } catch (e: Exception) { /* fallback */ }
        }
        val q = URLEncoder.encode(keyword, "UTF-8")
        val html = Http.getText("https://www.themoviedb.org/search/movie?query=$q&language=zh-CN", tmdbHeaders())
        val out = mutableListOf<TmdbResult>(); val seen = mutableSetOf<String>()
        val linkRe = Regex("""href="/movie/(\d+)[^"]*"[^>]*>(?:(?!</a>).)*?<h2[^>]*>([^<]+)</h2>""", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
        for (m in linkRe.findAll(html)) {
            val id = m.groupValues[1]; if (id in seen) continue; seen.add(id)
            out.add(TmdbResult(id.toInt(), cleanSeriesName(m.groupValues[2].trim()), "", "", ""))
            if (out.size >= 10) break
        }
        return out to "scrape"
    }

    fun tmdbSearch(keyword: String, apiKey: String): Pair<List<TmdbResult>, String> {
        if (apiKey.isNotBlank()) {
            try { return tmdbApiSearch(keyword, apiKey) to "api" } catch (e: Exception) { /* fallback */ }
        }
        return tmdbScrapeSearch(keyword) to "scrape"
    }

    fun tmdbFetch(id: Int, season: Int, apiKey: String): Pair<Map<String, String>, String> {
        if (apiKey.isNotBlank()) {
            try { return tmdbApiSeason(id, season, apiKey) to "api" } catch (e: Exception) { /* fallback */ }
        }
        return tmdbScrapeSeason(id, season) to "scrape"
    }

    private fun tmdbHeaders() = mapOf(
        "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Accept-Language" to "zh-CN,zh;q=0.9,en;q=0.8")
}

/** TVmaze: free, no API key, generous limits — the fast fallback when TMDB is slow or 429s. */
fun tvmazeSearch(keyword: String): List<TmdbResult> {
    val q = URLEncoder.encode(keyword, "UTF-8")
    val arr = JSONArray(Http.getText("https://api.tvmaze.com/search/shows?q=$q", timeoutMs = 8000))
    val out = mutableListOf<TmdbResult>()
    for (i in 0 until minOf(arr.length(), 10)) {
        val show = arr.optJSONObject(i)?.optJSONObject("show") ?: continue
        val img = show.optJSONObject("image")?.optString("medium", "") ?: ""
        val summary = show.optString("summary", "").replace(Regex("<[^>]+>"), "").trim().take(120)
        out.add(TmdbResult(show.optInt("id"), cleanSeriesName(show.optString("name")),
            summary, show.optString("premiered", "").take(4), img))
    }
    return out
}

fun tvmazeEpisodes(id: Int, season: Int): Map<String, String> {
    val arr = JSONArray(Http.getText("https://api.tvmaze.com/shows/$id/episodes", timeoutMs = 8000))
    val out = mutableMapOf<String, String>()
    for (i in 0 until arr.length()) {
        val e = arr.optJSONObject(i) ?: continue
        if (e.optInt("season") == season) {
            val name = e.optString("name")
            if (name.isNotEmpty()) out[e.optInt("number").toString()] = name
        }
    }
    return out
}

/** Detect media tags straight from the release filename: resolution, codec, HDR, audio, language. */
fun detectMediaParams(filename: String): List<String> {
    val u = filename.uppercase()
    val out = mutableListOf<String>()
    fun has(vararg pats: String) = pats.any { u.contains(it) }
    when {
        has("2160P") || Regex("""(^|[\s._-])4K([\s._-]|$)""").containsMatchIn(u) -> out += "4K"
        has("1080P") -> out += "1080p"
        has("720P") -> out += "720p"
        has("480P") -> out += "480p"
    }
    when {
        has("HDR10+") -> out += "HDR10+"
        has("HDR10") -> out += "HDR10"
        has("DOLBY VISION") || Regex("""(^|[\s._-])DV([\s._-]|$)""").containsMatchIn(u) -> out += "DV"
        has("HDR") -> out += "HDR"
    }
    when {
        has("X265", "HEVC", "H.265", "H265") -> out += "HEVC"
        has("X264", "H.264", "H264", "AVC") -> out += "H.264"
        has("VP9") -> out += "VP9"
        has("AV1") -> out += "AV1"
    }
    when {
        has("DTS-HD", "DTSHD") -> out += "DTS-HD"
        has("TRUEHD") -> out += "TrueHD"
        has("ATMOS") -> out += "Atmos"
        has("DTS") -> out += "DTS"
        has("EAC3", "DD+", "DDP") -> out += "DD+"
        has("AC3") -> out += "AC3"
        has("AAC") -> out += "AAC"
        has("FLAC") -> out += "FLAC"
    }
    when {
        has("中英", "中英字幕", "中英双字", "中英双语") -> out += "中英字幕"
        has("中字", "简中", "繁中") -> out += "中字"
        has("国语", "国配") -> out += "国语"
        has("粤语") -> out += "粤语"
    }
    return out
}
