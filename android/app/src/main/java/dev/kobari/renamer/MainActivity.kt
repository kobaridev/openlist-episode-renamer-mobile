package dev.kobari.renamer

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.BorderStroke
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import kotlinx.coroutines.delay
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

val MEDIA_EXTS = listOf("mp4","mkv","avi","ts","flv","wmv","mov","m4v","webm","mpg","mpeg","3gp","asf","srt","ass","ssa")
val MEDIA_RE = Regex("""\.(${MEDIA_EXTS.joinToString("|")})$""", RegexOption.IGNORE_CASE)
val PRESETS = listOf("1080p","4K","HDR","HDR10","DV","DTS-HD","中英字幕")
const val DEFAULT_TMDB_KEY = "08a6bef260044f70c150251c79f2e476"

fun pad2(n: String): String = (n.ifEmpty { "0" }).padStart(2, '0')
fun humanSize(b: Long): String {
    if (b <= 0) return ""
    if (b < 1024) return "$b B"
    val u = listOf("KB","MB","GB","TB"); var v = b.toDouble(); var i = -1
    do { v /= 1024; i++ } while (v >= 1024 && i < u.size - 1)
    return String.format("%.1f %s", v, u[i])
}
fun parentOf(p: String): String {
    val t = p.trimEnd('/'); val i = t.lastIndexOf('/')
    return if (i <= 0) "/" else t.substring(0, i)
}
fun dirNameOf(p: String): String = p.trimEnd('/').split('/').filter { it.isNotEmpty() }.lastOrNull() ?: ""
fun natCmp(a: String, b: String): Int {
    val ra = Regex("""\d+|\D+""").findAll(a.lowercase()).map { it.value }.toList()
    val rb = Regex("""\d+|\D+""").findAll(b.lowercase()).map { it.value }.toList()
    for (i in 0 until minOf(ra.size, rb.size)) {
        val x = ra[i]; val y = rb[i]
        val c = if (x.first().isDigit() && y.first().isDigit()) (x.toLongOrNull() ?: 0).compareTo(y.toLongOrNull() ?: 0) else x.compareTo(y)
        if (c != 0) return c
    }
    return ra.size.compareTo(rb.size)
}

class RowState(val name: String, validIn: Boolean, info: EpisodeInfo) {
    var names: List<String> = listOf(name)
    var valid by mutableStateOf(validIn)
    var title by mutableStateOf(info.title)
    var season by mutableStateOf(info.season)
    var episode by mutableStateOf(info.episode)
    var epTitle by mutableStateOf("")
    var year by mutableStateOf("")
    var tags by mutableStateOf("")
}

class AppState(private val prefs: SharedPreferences) {
    var renamer: Renamer? = null
    var loggedIn by mutableStateOf(false)
    var loading by mutableStateOf(false)
    var loadError by mutableStateOf("")
    var committing by mutableStateOf(false)
    var currentPath by mutableStateOf("/")
    var directories by mutableStateOf<List<FsItem>>(emptyList())
    var files by mutableStateOf<List<FsItem>>(emptyList())
    var rows by mutableStateOf<List<RowState>>(emptyList())
    var user by mutableStateOf("")
    var openlistOk by mutableStateOf(false)
    val dirCache = mutableMapOf<String, Triple<List<FsItem>, List<FsItem>, List<RowState>>>()
    var editingRow by mutableStateOf<RowState?>(null)
    var toolsOpen by mutableStateOf(false)
    var selected by mutableStateOf<Set<String>>(emptySet())
    var batchOpen by mutableStateOf(false)

    var scrapeSource by mutableStateOf(prefs.getString("scrape_source", "auto") ?: "auto")
    val tmdbSearchCache = mutableMapOf<String, List<TmdbResult>>()
    val episodeCache = mutableMapOf<String, Map<String, String>>()
    var tmdbApiKey by mutableStateOf(prefs.getString("tmdb_api_key", DEFAULT_TMDB_KEY) ?: DEFAULT_TMDB_KEY)
    var delimiter by mutableStateOf(prefs.getString("delimiter", ".") ?: ".")
    var useEpisodeTitle by mutableStateOf(prefs.getBoolean("use_episode_title", true))
    var defaultSeason by mutableStateOf(prefs.getString("default_season", "1") ?: "1")
    var epStart by mutableStateOf(prefs.getString("default_episode_start", "1") ?: "1")
    var darkTheme by mutableStateOf(prefs.getString("theme", "light") == "dark")

    var mediaType by mutableStateOf(prefs.getString("media_type", "tv") ?: "tv")
    val dirMediaType = mutableMapOf<String, String>()

    var tmdbKeyword by mutableStateOf("")
    var tmdbSeason by mutableStateOf(defaultSeason)
    var tmdbResults by mutableStateOf<List<TmdbResult>>(emptyList())
    var tmdbSelected by mutableStateOf<TmdbResult?>(null)
    var tmdbEpisodes by mutableStateOf<Map<String, String>>(emptyMap())
    var tmdbSearching by mutableStateOf(false)
    var tmdbFetching by mutableStateOf(false)
    var mediaParams by mutableStateOf<List<String>>(emptyList())

    // rename progress
    var commitTotal by mutableStateOf(0)
    var commitDoneCount by mutableStateOf(0)
    var commitFailedNames by mutableStateOf<List<String>>(emptyList())
    var commitFinished by mutableStateOf(false)

    // per-directory scrape memory: selected show, season, episode titles
    val dirScrape = mutableMapOf<String, Triple<TmdbResult, String, Map<String, String>>>()
    fun saveScrape() {
        tmdbSelected?.let { dirScrape[currentPath] = Triple(it, tmdbSeason, tmdbEpisodes) }
        dirMediaType[currentPath] = mediaType
    }
    fun restoreScrape() {
        dirMediaType[currentPath]?.let { mediaType = it }
        dirScrape[currentPath]?.let { (sel, season, eps) ->
            tmdbSelected = sel; tmdbSeason = season; tmdbEpisodes = eps
            fillFromSelection()
        }
    }

    fun saveSetting() {
        prefs.edit()
            .putString("media_type", mediaType)
            .putString("scrape_source", scrapeSource)
            .putString("tmdb_api_key", tmdbApiKey).putString("delimiter", delimiter)
            .putBoolean("use_episode_title", useEpisodeTitle)
            .putString("default_season", defaultSeason).putString("default_episode_start", epStart)
            .putString("theme", if (darkTheme) "dark" else "light").apply()
    }

    fun previewName(r: RowState): String {
        val d = delimiter.ifEmpty { "." }
        val title = r.title.ifEmpty { "UNKNOWN" }
        val ext = if (r.name.contains('.')) r.name.substring(r.name.lastIndexOf('.')) else ""
        if (mediaType == "movie") {
            var name = title
            if (r.year.isNotBlank()) name += " (${r.year.trim()})"
            if (r.tags.isNotBlank()) {
                val parts = r.tags.split(Regex("""[,，;；|]""")).map { it.trim() }.filter { it.isNotEmpty() }
                if (parts.isNotEmpty()) name += d + parts.joinToString(d)
            }
            return name + ext
        }
        var name = title + d + "S" + pad2(r.season) + "E" + pad2(r.episode)
        if (useEpisodeTitle && r.epTitle.isNotBlank()) name += d + r.epTitle.trim()
        if (r.tags.isNotBlank()) {
            val parts = r.tags.split(Regex("""[,，;；|]""")).map { it.trim() }.filter { it.isNotEmpty() }
            if (parts.isNotEmpty()) name += d + parts.joinToString(d)
        }
        return name + ext
    }
    fun previewBase(r: RowState): String {
        val full = previewName(r)
        return if (full.contains('.')) full.substring(0, full.lastIndexOf('.')) else full
    }
    val renameableCount: Int get() = rows.count { previewName(it) != it.name }

    fun syncEpisodes() {
        if (mediaType == "movie") return
        val bcount = mutableMapOf<String, Int>()
        for (r in rows) {
            val b = r.name.replace(Regex("""\.[^.]+$"""), "").lowercase()
            bcount[b] = (bcount[b] ?: 0) + 1
        }
        val groups = mutableMapOf<String, MutableList<Int>>()
        for ((i, r) in rows.withIndex()) {
            val b = r.name.replace(Regex("""\.[^.]+$"""), "").lowercase()
            val key = if ((bcount[b] ?: 0) > 1) "b$b"
            else {
                val s = r.season.padStart(2, '0'); val e = r.episode.padStart(2, '0')
                if (s != "00" && e != "00" && s.isNotEmpty() && e.isNotEmpty()) "s${s}e$e" else "b$b"
            }
            groups.getOrPut(key) { mutableListOf() }.add(i)
        }
        for (g in groups.values) {
            if (g.size < 2) continue
            val anchor = rows[g[0]]
            val titled = g.map { rows[it] }.firstOrNull { it.epTitle.isNotBlank() }
            for (i in g) {
                val r = rows[i]
                r.title = anchor.title; r.season = anchor.season; r.episode = anchor.episode; r.tags = anchor.tags
                if (titled != null && titled !== r) r.epTitle = titled.epTitle
            }
        }
    }

    fun applyEpisodeNumbers() {
        if (rows.isEmpty()) return
        val season = tmdbSeason.ifEmpty { "1" }
        var ep = epStart.toIntOrNull() ?: 1
        val groups = mutableListOf<String>(); val seen = mutableSetOf<String>()
        for (r in rows) {
            val key = r.name.replace(Regex("""\.[^.]+$"""), "").lowercase()
            if (seen.add(key)) groups.add(key)
        }
        for (key in groups) {
            for (r in rows) {
                if (r.name.replace(Regex("""\.[^.]+$"""), "").lowercase() == key) {
                    r.season = season; r.episode = ep.toString()
                }
            }
            ep++
        }
        syncEpisodes()
    }

    fun fillFromSelection() {
        val sel = tmdbSelected ?: return
        if (mediaType == "movie") {
            for (r in rows) { r.title = sel.name; r.year = sel.year }
            syncEpisodes()
            return
        }
        var n = 0
        for (r in rows) {
            r.title = sel.name
            if (r.season.isEmpty()) r.season = tmdbSeason.ifEmpty { "1" }
            val ep = r.episode.toIntOrNull() ?: ((epStart.toIntOrNull() ?: 1) + n)
            r.episode = ep.toString()
            val t = tmdbEpisodes[ep.toString()]
            if (useEpisodeTitle && t != null) r.epTitle = t.trim()
            n++
        }
        syncEpisodes()
    }

    fun applyTags() {
        val joined = mediaParams.joinToString(",")
        for (r in rows) r.tags = joined
        syncEpisodes()
    }
}

suspend fun relogin(state: AppState, prefs: SharedPreferences): Boolean {
    val old = state.renamer ?: return false
    return try {
        val r = Renamer(old.baseUrlRaw, old.username, old.password)
        val ok = withContext(Dispatchers.IO) { r.login() }
        if (ok) { r.saveToken(prefs); state.renamer = r }
        ok
    } catch (e: Exception) { false }
}

suspend fun loadDir(state: AppState, prefs: SharedPreferences, force: Boolean = false) {
    val r = state.renamer ?: return
    if (!force) {
        state.dirCache[state.currentPath]?.let { (dirs, files, rows) ->
            state.directories = dirs; state.files = files; state.rows = rows
            state.openlistOk = true; state.loadError = ""; state.loading = false
            if (state.dirMediaType[state.currentPath] == null) {
                val seRe = Regex("""(?i)S\d{1,2}[\s._\-]*E\d{1,3}""")
                state.mediaType = if (state.files.any { seRe.containsMatchIn(it.name) }) "tv" else "movie"
            }
            state.restoreScrape()
            return
        }
    }
    state.loading = true; state.loadError = ""
    try {
        var items: List<FsItem>? = null
        try {
            items = withContext(Dispatchers.IO) { r.listContents(state.currentPath) }
        } catch (e: Exception) {
            // Only an auth-looking failure earns a re-login + retry; a slow or
            // unreachable server should fail fast instead of stacking round-trips.
            val msg = (e.message ?: "").lowercase()
            val authLike = "token" in msg || "401" in msg || "unauthorized" in msg || "登录" in msg || "invalid" in msg
            if (authLike && relogin(state, prefs)) {
                items = withContext(Dispatchers.IO) { state.renamer!!.listContents(state.currentPath) }
            } else throw e
        }
        val list = items!!
        state.directories = list.filter { it.isDir }.sortedWith { x, y -> natCmp(x.name, y.name) }
        state.files = list.filter { !it.isDir }.sortedWith { x, y -> natCmp(x.name, y.name) }
        fun extPri(name: String): Int {
            val e = name.substringAfterLast('.', "").lowercase()
            return when (e) {
                "mp4","mkv","avi","ts","mov","webm","flv","wmv","m4v","mpg","mpeg" -> 0
                "srt","ass","ssa","vtt" -> 1
                else -> 2
            }
        }
        // Group by parsed season/episode, not by filename: a subtitle and its video often
        // carry different release tags, but they are the same episode.
        val seRe = Regex("""(?i)S\d{1,2}[\s._\-]*E\d{1,3}""")
        val parsed = state.files.map { f ->
            f to withContext(Dispatchers.IO) { state.renamer!!.extractEpisodeInfo(f.name) }
        }
        val groups = parsed.groupBy { (f, info) ->
            val sn = info.season.toIntOrNull(); val ep = info.episode.toIntOrNull()
            if (seRe.containsMatchIn(f.name) && sn != null && ep != null) "se_${sn}_$ep"
            else "base_" + f.name.replace(Regex("""\.[^.]+$"""), "").lowercase()
        }
        state.rows = groups.values.map { g ->
            val sorted = g.sortedWith { a, b ->
                val c = extPri(a.first.name).compareTo(extPri(b.first.name))
                if (c != 0) c else natCmp(a.first.name, b.first.name)
            }
            val (main, info) = sorted.first()
            RowState(main.name, true, info).also { row ->
                row.names = sorted.map { it.first.name }
                row.tags = detectMediaParams(main.name).joinToString(",")
            }
        }.sortedWith { a, b ->
            val sa = a.season.toIntOrNull() ?: 999; val sb = b.season.toIntOrNull() ?: 999
            val ea = a.episode.toIntOrNull() ?: 99999; val eb = b.episode.toIntOrNull() ?: 99999
            if (sa != sb) sa.compareTo(sb) else if (ea != eb) ea.compareTo(eb) else natCmp(a.name, b.name)
        }
        state.openlistOk = true; state.selected = emptySet()
        state.dirCache[state.currentPath] = Triple(state.directories, state.files, state.rows)
        if (state.dirMediaType[state.currentPath] == null) {
            state.mediaType = if (state.files.any { seRe.containsMatchIn(it.name) }) "tv" else "movie"
        }
        state.restoreScrape()
    } catch (e: Exception) {
        state.openlistOk = false
        throw e
    } finally { state.loading = false }
}

suspend fun doLogin(state: AppState, prefs: SharedPreferences, base: String, user: String, pass: String): String? {
    return withContext(Dispatchers.IO) {
        try {
            var b = base.trim()
            if (b.isEmpty()) b = "http://127.0.0.1:5244"
            if (!b.startsWith("http://") && !b.startsWith("https://")) {
                val host = b.split(Regex("[/:]"))[0].lowercase()
                val useHttp = host == "127.0.0.1" || host == "localhost" || host.endsWith(".internal") ||
                    Regex("""^\d{1,3}(\.\d{1,3}){3}$""").matches(host)
                b = (if (useHttp) "http://" else "https://") + b
            }
            val r = Renamer(b, user, pass)
            r.loadToken(prefs)
            val hasToken = r.token != null
            if ((hasToken && r.validateCurrentUser()) || r.login()) {
                r.saveToken(prefs)
                state.renamer = r; state.user = user; state.openlistOk = true; state.loggedIn = true
                prefs.edit().putString("base_url", b).putString("username", user).putString("password", pass).apply()
                null
            } else "登录失败，请检查账号密码"
        } catch (e: Exception) { e.message ?: "网络错误" }
    }
}

fun Renamer.loadToken(prefs: SharedPreferences) { token = prefs.getString("token_$username@$baseUrl", null) }
fun Renamer.saveToken(prefs: SharedPreferences) { token?.let { prefs.edit().putString("token_$username@$baseUrl", it).apply() } }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("settings", Context.MODE_PRIVATE)
        setContent {
            val state = remember { AppState(prefs) }
            RenamerTheme(dark = state.darkTheme) {
                val bg = if (state.darkTheme)
                    Brush.verticalGradient(listOf(Color(0xFF16305A), Color(0xFF0C1A30), Color(0xFF0A1526)))
                else
                    Brush.verticalGradient(listOf(Color(0xFFD9E9FF), Color(0xFFF2F7FF), Color(0xFFFFFFFF)))
                Box(Modifier.fillMaxSize().background(bg)) {
                    if (state.loggedIn) MainScreen(state, prefs) else LoginScreen(state, prefs)
                }
            }
        }
    }
}

private val BlueLight = lightColorScheme(
    primary = Color(0xFF0B57D0), onPrimary = Color.White,
    primaryContainer = Color(0xFFD3E3FD), onPrimaryContainer = Color(0xFF041E49),
    secondary = Color(0xFF00639B), background = Color(0xFFF4F8FE), onBackground = Color(0xFF1F1F1F),
    surface = Color.White, onSurface = Color(0xFF1F1F1F),
    surfaceVariant = Color(0xFFEAF1FB), onSurfaceVariant = Color(0xFF444746),
    outline = Color(0xFFC4C7C5), outlineVariant = Color(0xFFE1E7EF),
    error = Color(0xFFB3261E)
)
private val BlueDark = darkColorScheme(
    primary = Color(0xFF8AB8FF), onPrimary = Color(0xFF08295C),
    primaryContainer = Color(0xFF1E4470), onPrimaryContainer = Color(0xFFD3E3FD),
    secondary = Color(0xFF7FCFFF), background = Color(0xFF0A1526), onBackground = Color(0xFFE6EEF9),
    surface = Color(0xFF132239), onSurface = Color(0xFFE6EEF9),
    surfaceVariant = Color(0xFF1D3252), onSurfaceVariant = Color(0xFFB9C9DE),
    outline = Color(0xFF3D5A85), outlineVariant = Color(0xFF243A5C),
    error = Color(0xFFF2B8B5)
)

@Composable
fun RenamerTheme(dark: Boolean, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (dark) BlueDark else BlueLight, content = content)
}

@Composable
fun LoginScreen(state: AppState, prefs: SharedPreferences) {
    var url by remember { mutableStateOf(prefs.getString("base_url", "")?.ifEmpty { "127.0.0.1:5244" } ?: "127.0.0.1:5244") }
    var username by remember { mutableStateOf(prefs.getString("username", "") ?: "") }
    var password by remember { mutableStateOf(prefs.getString("password", "") ?: "") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun attempt() {
        if (busy) return
        if (url.isBlank()) { error = "服务器地址不能为空"; return }
        if (username.isBlank()) { error = "用户名不能为空"; return }
        if (password.isBlank()) { error = "密码不能为空"; return }
        busy = true; error = null
        scope.launch {
            error = doLogin(state, prefs, url, username, password)
            busy = false
        }
    }
    LaunchedEffect(Unit) {
        if (url.isNotBlank() && username.isNotBlank() && password.isNotBlank()) attempt()
    }
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 40.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        androidx.compose.foundation.Image(
            painter = painterResource(R.drawable.login_logo), contentDescription = null,
            modifier = Modifier.size(108.dp).clip(RoundedCornerShape(28.dp))
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(28.dp)),
            contentScale = ContentScale.Crop)
        Text("OpenList 影视重命名", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onBackground)
        Text("连接你的 OpenList 服务器", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(4.dp))
        OutlinedTextField(url, { url = it }, label = { Text("服务器地址") }, placeholder = { Text("例如 192.168.1.10:5244") },
            singleLine = true, modifier = Modifier.fillMaxWidth(), leadingIcon = { Icon(Icons.Filled.Cloud, null) })
        OutlinedTextField(username, { username = it }, label = { Text("用户名") }, singleLine = true,
            modifier = Modifier.fillMaxWidth(), leadingIcon = { Icon(Icons.Filled.Person, null) })
        OutlinedTextField(password, { password = it }, label = { Text("密码") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth(),
            leadingIcon = { Icon(Icons.Filled.Lock, null) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
        if (error != null) Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        Button(onClick = { attempt() }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(50.dp), shape = RoundedCornerShape(50)) {
            if (busy) CircularProgressIndicator(modifier = Modifier.size(20.dp), color = MaterialTheme.colorScheme.onPrimary)
            else Text("连接")
        }
        Spacer(Modifier.height(26.dp))
        val ctx = LocalContext.current
        fun openUrl(u: String) { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(u))) }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ShieldBadge("GitHub", "KoBariDev") { openUrl("https://github.com/KoBariDev") }
                ShieldBadge("Blog", "hub.131714.xyz") { openUrl("https://hub.131714.xyz") }
            }
            ShieldBadge("Repo", "openlist-episode-renamer") { openUrl("https://github.com/KoBariDev/openlist-episode-renamer") }
        }
    }
}

@Composable
fun ShieldBadge(label: String, value: String, onClick: () -> Unit) {
    Row(Modifier.clip(RoundedCornerShape(7.dp)).clickable { onClick() }) {
        Box(Modifier.background(Color(0xFF2F3B4C)).padding(horizontal = 8.dp, vertical = 5.dp)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = Color.White)
        }
        Box(Modifier.background(Color(0xFF0B57D0)).padding(horizontal = 8.dp, vertical = 5.dp)) {
            Text(value, style = MaterialTheme.typography.labelSmall, color = Color.White, fontWeight = FontWeight.SemiBold)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(state: AppState, prefs: SharedPreferences) {
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var showSettings by remember { mutableStateOf(false) }
    var showConfirm by remember { mutableStateOf(false) }
    var singleRenameRow by remember { mutableStateOf<RowState?>(null) }
    var renameDirTarget by remember { mutableStateOf<FsItem?>(null) }
    var dirRenameText by remember { mutableStateOf("") }

    fun reload(force: Boolean = false) {
        scope.launch {
            try { loadDir(state, prefs, force) }
            catch (e: Exception) { state.loadError = e.message ?: "加载失败"; snackbar.showSnackbar("加载失败：${state.loadError}", duration = SnackbarDuration.Short) }
        }
    }
    val listState = rememberLazyListState()
    val scrollMemory = remember { mutableMapOf<String, Pair<Int, Int>>() }
    LaunchedEffect(Unit) { reload() }
    LaunchedEffect(state.currentPath) { state.toolsOpen = false }
    // keep the scroll position fresh for the current directory
    LaunchedEffect(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset) {
        scrollMemory[state.currentPath] = listState.firstVisibleItemIndex to listState.firstVisibleItemScrollOffset
    }
    // restore the saved position once the new directory's rows are in
    LaunchedEffect(state.rows) {
        val (idx, off) = scrollMemory[state.currentPath] ?: return@LaunchedEffect
        if (state.rows.isNotEmpty() && listState.firstVisibleItemIndex != idx) listState.scrollToItem(idx, off)
    }
    val pillBg by animateColorAsState(
        if (state.toolsOpen) MaterialTheme.colorScheme.surface else MaterialTheme.colorScheme.primary,
        animationSpec = tween(300), label = "pillBg")
    val pillFg by animateColorAsState(
        if (state.toolsOpen) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onPrimary,
        animationSpec = tween(300), label = "pillFg")
    BackHandler(enabled = state.currentPath != "/") {
        state.currentPath = parentOf(state.currentPath); reload()
    }

    Scaffold(
        containerColor = Color.Transparent,
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Surface(shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f), shadowElevation = 8.dp) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (state.selected.isNotEmpty()) {
                            Text("已选 ${state.selected.size}", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                            TextButton(onClick = { state.selected = state.rows.map { it.name }.toSet() }) { Text("全选") }
                            TextButton(onClick = { state.selected = emptySet() }) { Text("取消") }
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { state.batchOpen = true }, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp), shape = RoundedCornerShape(50)) {
                                Icon(Icons.Filled.Edit, null, Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("批量编辑")
                            }
                            Button(onClick = { showConfirm = true },
                                enabled = state.rows.any { it.name in state.selected && state.previewName(it) != it.name } && !state.committing,
                                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp), shape = RoundedCornerShape(50)) {
                                Icon(Icons.Filled.DriveFileRenameOutline, null, Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("重命名")
                            }
                        } else {
                            Text("${state.rows.size} 文件 · ${state.renameableCount} 待改", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { if (state.renameableCount > 0) showConfirm = true },
                                enabled = state.renameableCount > 0 && !state.committing, shape = RoundedCornerShape(50)) {
                                if (state.committing) CircularProgressIndicator(Modifier.size(16.dp), color = MaterialTheme.colorScheme.onPrimary)
                                else Icon(Icons.Filled.DriveFileRenameOutline, null, Modifier.size(16.dp))
                                Spacer(Modifier.width(6.dp)); Text("重命名")
                            }
                        }
                    }
                }
                Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
                    shadowElevation = 10.dp, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                    val navTint = if (state.darkTheme) Color.White else MaterialTheme.colorScheme.onSurface
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { state.currentPath = "/"; reload() }) { Icon(Icons.Filled.Home, "根目录", tint = navTint) }
                        IconButton(onClick = { if (state.currentPath != "/") { state.currentPath = parentOf(state.currentPath); reload() } },
                            enabled = state.currentPath != "/") { Icon(Icons.Filled.ArrowBack, "上级目录", tint = navTint) }
                        IconButton(onClick = { reload(true) }) { Icon(Icons.Filled.Refresh, "刷新", tint = navTint) }
                        IconButton(onClick = { state.darkTheme = !state.darkTheme; state.saveSetting() }) {
                            Icon(if (state.darkTheme) Icons.Filled.LightMode else Icons.Filled.DarkMode, "主题", tint = navTint)
                        }
                        IconButton(onClick = { showSettings = true }) { Icon(Icons.Filled.Info, "关于", tint = navTint) }
                        IconButton(onClick = {
                            prefs.edit().remove("password").apply()
                            state.renamer = null; state.loggedIn = false; state.rows = emptyList()
                        }) { Icon(Icons.Filled.Logout, "退出", tint = navTint) }
                    }
                }
            }
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 4.dp)) {
                item {
                    Text(dirNameOf(state.currentPath).ifEmpty { "根目录" }, style = MaterialTheme.typography.headlineSmall,
                        color = if (state.darkTheme) Color.White else MaterialTheme.colorScheme.onBackground,
                        fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp))
                }
                // breadcrumb
                item {
                    val parts = state.currentPath.split('/').filter { it.isNotEmpty() }
                    LazyRow(contentPadding = PaddingValues(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        item {
                            AssistChip(onClick = { state.currentPath = "/"; reload() }, label = { Text("/", style = MaterialTheme.typography.labelMedium) },
                                leadingIcon = { Icon(Icons.Filled.Home, null, Modifier.size(14.dp)) })
                        }
                        items(parts.size) { i ->
                            val p = "/" + parts.subList(0, i + 1).joinToString("/")
                            AssistChip(onClick = { state.currentPath = p; reload() },
                                label = { Text(parts[i], style = MaterialTheme.typography.labelMedium, maxLines = 1) })
                        }
                    }
                }
                // tools toggle: one prominent pill button
                item {
                    Button(onClick = { state.toolsOpen = !state.toolsOpen },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp).height(50.dp),
                        shape = RoundedCornerShape(50),
                        colors = ButtonDefaults.buttonColors(containerColor = pillBg, contentColor = pillFg),
                        elevation = ButtonDefaults.buttonElevation(defaultElevation = 4.dp)) {
                        Icon(Icons.Filled.Build, null, Modifier.size(19.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(if (state.toolsOpen) "收起批量工具" else "批量工具 · TMDB · 集名刮削 · 编号 · 参数",
                            style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.width(6.dp))
                        Icon(if (state.toolsOpen) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, Modifier.size(19.dp))
                    }
                }
                item {
                    AnimatedVisibility(visible = state.toolsOpen,
                        enter = expandVertically(animationSpec = tween(350)) + fadeIn(animationSpec = tween(250)),
                        exit = shrinkVertically(animationSpec = tween(300)) + fadeOut(animationSpec = tween(200))) {
                        ToolsPanel(state, snackbar)
                    }
                }
                // directories
                items(state.directories) { dir ->
                    Card(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 3.dp), shape = RoundedCornerShape(22.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                        elevation = CardDefaults.cardElevation(defaultElevation = 3.dp)) {
                        Row(Modifier.fillMaxWidth().clickable {
                            state.currentPath = if (state.currentPath == "/") "/${dir.name}" else "${state.currentPath}/${dir.name}"
                            reload()
                        }.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(38.dp).clip(RoundedCornerShape(13.dp))
                                .background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                                Icon(Icons.Filled.Folder, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                            }
                            Spacer(Modifier.width(10.dp))
                            Text(dir.name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f))
                            IconButton(onClick = { renameDirTarget = dir; dirRenameText = dir.name }, modifier = Modifier.size(32.dp)) {
                                Icon(Icons.Filled.Edit, "重命名目录", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Icon(Icons.Filled.ChevronRight, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                // error / empty states
                if (state.loadError.isNotBlank()) item {
                    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Filled.CloudOff, null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(32.dp))
                        Spacer(Modifier.height(6.dp))
                        Text("目录加载失败", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        Text(state.loadError, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.height(8.dp))
                        OutlinedButton(onClick = { reload() }) { Text("重试") }
                    }
                }
                if (!state.loading && state.loadError.isBlank() && state.rows.isEmpty()) item {
                    Text("当前目录没有可重命名的媒体文件", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
                }
                // files (compact rows)
                items(state.rows, key = { it.name }) { row ->
                    val preview = state.previewName(row)
                    val changed = preview != row.name
                    val checked = state.selected.contains(row.name)
                    val grp = if (row.names.size > 1) " · 同名 ${row.names.size} 个" else ""
                    Card(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 3.dp), shape = RoundedCornerShape(22.dp),
                        elevation = CardDefaults.cardElevation(defaultElevation = 3.dp),
                        colors = CardDefaults.cardColors(containerColor = if (checked) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f) else MaterialTheme.colorScheme.surface),
                        border = BorderStroke(1.dp, if (checked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant)) {
                        Row(Modifier.fillMaxWidth().clickable { state.editingRow = row }.padding(end = 10.dp, top = 2.dp, bottom = 2.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(checked, { state.selected = if (it) state.selected + row.name else state.selected - row.name },
                                modifier = Modifier.size(40.dp))
                            Column(Modifier.weight(1f).padding(vertical = 6.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text("原名", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Spacer(Modifier.width(4.dp))
                                    Text(row.name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f))
                                    Spacer(Modifier.width(8.dp))
                                    if (state.mediaType == "movie") {
                                        if (row.year.isNotBlank()) Box(Modifier.clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.primaryContainer)
                                            .padding(horizontal = 7.dp, vertical = 2.dp)) {
                                            Text(row.year, style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.onPrimaryContainer, fontWeight = FontWeight.Bold)
                                        }
                                    } else Box(Modifier.clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.primaryContainer)
                                        .padding(horizontal = 7.dp, vertical = 2.dp)) {
                                        Text("S${pad2(row.season)}E${pad2(row.episode)}", style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onPrimaryContainer, fontWeight = FontWeight.Bold)
                                    }
                                }
                                if (changed) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text("新名", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                                        Spacer(Modifier.width(4.dp))
                                        Text(buildAnnotatedString {
                                            append(diffAnnotated(row.name, preview, MaterialTheme.colorScheme.onSurfaceVariant, MaterialTheme.colorScheme.primary))
                                            withStyle(SpanStyle(color = MaterialTheme.colorScheme.onSurfaceVariant)) { append(grp) }
                                        }, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                } else {
                                    Text("未修改" + grp, style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
            if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth().align(Alignment.TopCenter))
        }
    }

    // ---- edit bottom sheet ----
    val editing = state.editingRow
    if (editing != null) {
        var singleKw by remember { mutableStateOf("") }
        var singleResults by remember { mutableStateOf<List<TmdbResult>>(emptyList()) }
        var singleSearching by remember { mutableStateOf(false) }
        fun doSingleSearch() {
            if (singleKw.isBlank() || singleSearching) return
            singleSearching = true
            scope.launch {
                try {
                    val kw = singleKw.trim()
                    val raw = withContext(Dispatchers.IO) {
                        if (state.mediaType == "movie") {
                            state.renamer!!.tmdbSearchMovie(kw, state.tmdbApiKey.trim()).first
                        } else when (state.scrapeSource) {
                            "tvmaze" -> tvmazeSearch(kw)
                            "tmdb" -> state.renamer!!.tmdbSearch(kw, state.tmdbApiKey.trim()).first
                            else -> try { state.renamer!!.tmdbSearch(kw, state.tmdbApiKey.trim()).first }
                                catch (e: Exception) { tvmazeSearch(kw) }
                        }
                    }
                    singleResults = raw.sortedBy { if (it.name.trim() == kw) 0 else 1 }
                    if (singleResults.isEmpty()) snackbar.showSnackbar("没有搜到结果", duration = SnackbarDuration.Short)
                } catch (e: Exception) { snackbar.showSnackbar("搜索失败：${e.message}", duration = SnackbarDuration.Short) }
                singleSearching = false
            }
        }
        LaunchedEffect(singleKw) {
            val kw = singleKw.trim()
            if (kw.isEmpty()) return@LaunchedEffect
            delay(600)
            if (singleKw.trim() == kw) doSingleSearch()
        }
        ModalBottomSheet(onDismissRequest = { state.editingRow = null }, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp), containerColor = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.onSurface) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(editing.name, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (editing.names.size > 1) Text("同名文件共 ${editing.names.size} 个（${editing.names.joinToString("、") { it.substringAfterLast('.', "") }}），改名会一起改",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                OutlinedTextField(editing.title, { editing.title = it; state.syncEpisodes() }, label = { Text(if (state.mediaType == "movie") "电影名" else "剧名") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    CompactInput(singleKw, { singleKw = it }, Modifier.weight(1f),
                        placeholder = if (state.mediaType == "movie") "搜索电影名，只填这一行" else "搜索剧名，只填这一行", heightDp = 42, onSearch = { doSingleSearch() })
                    FilledIconButton(onClick = { doSingleSearch() }, enabled = !singleSearching) {
                        if (singleSearching) CircularProgressIndicator(Modifier.size(18.dp)) else Icon(Icons.Filled.Search, "搜索", Modifier.size(18.dp))
                    }
                }
                if (singleResults.isNotEmpty()) {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(singleResults) { res ->
                            Column(Modifier.width(80.dp).clickable {
                                editing.title = res.name
                                if (state.mediaType == "movie") {
                                    editing.year = res.year
                                    state.syncEpisodes()
                                    scope.launch { snackbar.showSnackbar("已填入电影名", duration = SnackbarDuration.Short) }
                                } else {
                                    state.syncEpisodes()
                                    scope.launch {
                                        try {
                                            val season = editing.season.toIntOrNull() ?: 1
                                            val eps = withContext(Dispatchers.IO) {
                                                when (state.scrapeSource) {
                                                    "tvmaze" -> tvmazeEpisodes(res.id, season)
                                                    "tmdb" -> state.renamer!!.tmdbFetch(res.id, season, state.tmdbApiKey.trim()).first
                                                    else -> try { state.renamer!!.tmdbFetch(res.id, season, state.tmdbApiKey.trim()).first }
                                                        catch (e: Exception) {
                                                            val alt = tvmazeSearch(res.name).firstOrNull()
                                                            if (alt != null) tvmazeEpisodes(alt.id, season) else emptyMap()
                                                        }
                                                }
                                            }
                                            val t = eps[editing.episode]
                                            if (state.useEpisodeTitle && t != null) editing.epTitle = t.trim()
                                            state.syncEpisodes()
                                            snackbar.showSnackbar("已填入剧名和集名", duration = SnackbarDuration.Short)
                                        } catch (e: Exception) { snackbar.showSnackbar("获取集名失败：${e.message}", duration = SnackbarDuration.Short) }
                                    }
                                }
                            }, horizontalAlignment = Alignment.CenterHorizontally) {
                                Box(Modifier.size(width = 70.dp, height = 104.dp).clip(RoundedCornerShape(12.dp))
                                    .background(MaterialTheme.colorScheme.surfaceVariant)) {
                                    if (res.poster.isNotEmpty()) PosterImage(res.poster)
                                    else Icon(Icons.Filled.Movie, null, Modifier.align(Alignment.Center), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Text(res.name, style = MaterialTheme.typography.labelSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                Text(res.year + if (state.mediaType == "movie") " · 电影" else " · 剧集",
                                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                if (state.mediaType == "movie") {
                    OutlinedTextField(editing.year, { editing.year = it.filter { c -> c.isDigit() }; state.syncEpisodes() },
                        label = { Text("年份") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(editing.season, { editing.season = it.filter { c -> c.isDigit() }; state.syncEpisodes() },
                            label = { Text("季") }, singleLine = true, modifier = Modifier.weight(1f),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                        OutlinedTextField(editing.episode, { editing.episode = it.filter { c -> c.isDigit() }; state.syncEpisodes() },
                            label = { Text("集") }, singleLine = true, modifier = Modifier.weight(1f),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                    }
                    OutlinedTextField(editing.epTitle, { editing.epTitle = it; state.syncEpisodes() }, label = { Text("集名（可选）") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                OutlinedTextField(editing.tags, { editing.tags = it; state.syncEpisodes() }, label = { Text("媒体参数，逗号分隔") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                val curTags = editing.tags.split(Regex("""[,，;；|]""")).map { it.trim() }.filter { it.isNotEmpty() }
                if (curTags.isNotEmpty()) {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(curTags) { t ->
                            InputChip(selected = true, onClick = {
                                editing.tags = curTags.filter { it != t }.joinToString(","); state.syncEpisodes()
                            }, label = { Text(t, style = MaterialTheme.typography.labelMedium) },
                            trailingIcon = { Icon(Icons.Filled.Close, null, Modifier.size(14.dp)) })
                        }
                    }
                }
                Text("新名：" + state.previewName(editing), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        singleRenameRow = editing; state.editingRow = null; showConfirm = true
                    }, enabled = state.previewName(editing) != editing.name, modifier = Modifier.weight(1f)) { Text("重命名此文件") }
                    OutlinedButton(onClick = { state.editingRow = null }, modifier = Modifier.weight(1f)) { Text("完成") }
                }
            }
        }
    }

    // ---- batch edit sheet ----
    if (state.batchOpen) {
        var bTitle by remember { mutableStateOf("") }
        var bSeason by remember { mutableStateOf("") }
        var bStart by remember { mutableStateOf("") }
        var bYear by remember { mutableStateOf("") }
        var bTags by remember { mutableStateOf("") }
        ModalBottomSheet(onDismissRequest = { state.batchOpen = false }, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp), containerColor = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.onSurface) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("批量编辑 ${state.selected.size} 个文件", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("留空的字段不改；填了起始集号会按列表顺序连续编号。", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(bTitle, { bTitle = it }, label = { Text(if (state.mediaType == "movie") "统一电影名" else "统一剧名") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                if (state.mediaType == "movie") {
                    OutlinedTextField(bYear, { bYear = it.filter { c -> c.isDigit() } }, label = { Text("统一年份") },
                        singleLine = true, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                } else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(bSeason, { bSeason = it.filter { c -> c.isDigit() } }, label = { Text("统一季号") },
                        singleLine = true, modifier = Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                    OutlinedTextField(bStart, { bStart = it.filter { c -> c.isDigit() } }, label = { Text("起始集号") },
                        singleLine = true, modifier = Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
                OutlinedTextField(bTags, { bTags = it }, label = { Text("统一媒体参数，逗号分隔") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                if (state.mediaType == "tv" && state.tmdbEpisodes.isNotEmpty()) {
                    Text("已刮削到 ${state.tmdbEpisodes.size} 集集名，应用时按集号自动填入。", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary)
                }
                Button(onClick = {
                    val targets = state.rows.filter { state.selected.contains(it.name) }
                    var ep = bStart.toIntOrNull()
                    for (r in targets) {
                        if (bTitle.isNotBlank()) r.title = bTitle.trim()
                        if (state.mediaType == "movie") {
                            if (bYear.isNotBlank()) r.year = bYear
                        } else {
                            if (bSeason.isNotBlank()) r.season = bSeason
                            if (ep != null) { r.episode = ep.toString(); ep++ }
                            val t = state.tmdbEpisodes[r.episode]
                            if (state.useEpisodeTitle && t != null) r.epTitle = t.trim()
                        }
                        if (bTags.isNotBlank()) r.tags = bTags
                    }
                    state.syncEpisodes()
                    state.batchOpen = false
                    scope.launch { snackbar.showSnackbar("已批量更新 ${targets.size} 个文件", duration = SnackbarDuration.Short) }
                }, modifier = Modifier.fillMaxWidth()) { Text("应用到所选") }
            }
        }
    }

    // ---- directory rename dialog ----
    if (renameDirTarget != null) {
        AlertDialog(
            containerColor = MaterialTheme.colorScheme.surface,
            titleContentColor = MaterialTheme.colorScheme.onSurface,
            textContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            onDismissRequest = { renameDirTarget = null },
            title = { Text("重命名目录") },
            text = { OutlinedTextField(dirRenameText, { dirRenameText = it }, label = { Text("新名称") }, singleLine = true) },
            confirmButton = {
                TextButton(onClick = {
                    val target = renameDirTarget!!; val newName = dirRenameText.trim()
                    renameDirTarget = null
                    if (newName.isNotBlank() && newName != target.name) scope.launch {
                        try {
                            withContext(Dispatchers.IO) { state.renamer!!.renameSingle(target.path, newName) }
                            state.dirCache.clear(); snackbar.showSnackbar("目录已重命名", duration = SnackbarDuration.Short); reload(true)
                        } catch (e: Exception) { snackbar.showSnackbar("重命名失败：${e.message}", duration = SnackbarDuration.Short) }
                    }
                }) { Text("确定") }
            },
            dismissButton = { TextButton(onClick = { renameDirTarget = null }) { Text("取消") } }
        )
    }

    // ---- confirm rename ----
    if (showConfirm) {
        val changes = when {
            singleRenameRow != null -> listOf(singleRenameRow!!)
            state.selected.isNotEmpty() -> state.rows.filter { it.name in state.selected && state.previewName(it) != it.name }
            else -> state.rows.filter { state.previewName(it) != it.name }
        }
        val running = state.committing
        val done = state.commitFinished
        AlertDialog(
            containerColor = MaterialTheme.colorScheme.surface,
            titleContentColor = MaterialTheme.colorScheme.onSurface,
            textContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            onDismissRequest = { if (!running) { showConfirm = false; state.commitFinished = false; singleRenameRow = null } },
            title = { Text(if (done) "重命名完成" else if (running) "正在重命名" else "确认重命名 ${changes.size} 个文件？") },
            text = {
                if (running || done) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        LinearProgressIndicator(
                            progress = { if (state.commitTotal > 0) state.commitDoneCount.toFloat() / state.commitTotal else 0f },
                            modifier = Modifier.fillMaxWidth())
                        Text("正在改 ${state.commitDoneCount}/${state.commitTotal}", style = MaterialTheme.typography.bodySmall)
                        if (done) {
                            val ok = state.commitDoneCount - state.commitFailedNames.size
                            Text("成功 $ok 个，失败 ${state.commitFailedNames.size} 个", style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.SemiBold)
                            if (state.commitFailedNames.isNotEmpty()) {
                                LazyColumn(Modifier.heightIn(max = 160.dp)) {
                                    items(state.commitFailedNames) { n ->
                                        Text(n, style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.error, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    LazyColumn(Modifier.heightIn(max = 320.dp)) {
                        items(changes) { r ->
                            Column(Modifier.padding(vertical = 3.dp)) {
                                Text(r.name, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(buildAnnotatedString {
                                    append("→ ")
                                    append(diffAnnotated(r.name, state.previewName(r),
                                        MaterialTheme.colorScheme.onSurfaceVariant, MaterialTheme.colorScheme.primary))
                                    if (r.names.size > 1) withStyle(SpanStyle(color = MaterialTheme.colorScheme.onSurfaceVariant)) {
                                        append("（同名共 ${r.names.size} 个一起改）")
                                    }
                                }, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
            },
            confirmButton = {
                if (done) {
                    TextButton(onClick = { showConfirm = false; state.commitFinished = false; singleRenameRow = null }) { Text("完成") }
                } else if (!running) {
                    TextButton(onClick = {
                        state.committing = true; state.commitFinished = false
                        state.commitFailedNames = emptyList(); state.commitDoneCount = 0
                        var total = 0
                        for (r in changes) for (fname in r.names) {
                            val ext = if (fname.contains('.')) fname.substring(fname.lastIndexOf('.')) else ""
                            if (state.previewBase(r) + ext != fname) total++
                        }
                        state.commitTotal = total
                        scope.launch {
                            try {
                                val alive = withContext(Dispatchers.IO) { state.renamer!!.validateCurrentUser() }
                                if (!alive) relogin(state, prefs)
                            } catch (e: Exception) { relogin(state, prefs) }
                            var okCount = 0
                            fun fullPath(name: String) = if (state.currentPath == "/") "/$name" else "${state.currentPath}/$name"
                            for (r in changes) {
                                val base = state.previewBase(r)
                                for (fname in r.names) {
                                    val ext = if (fname.contains('.')) fname.substring(fname.lastIndexOf('.')) else ""
                                    val newName = base + ext
                                    if (newName == fname) continue
                                    try {
                                        val ok = withContext(Dispatchers.IO) { state.renamer!!.renameSingle(fullPath(fname), newName) }
                                        if (ok) okCount++ else state.commitFailedNames = state.commitFailedNames + fname
                                    } catch (e: Exception) { state.commitFailedNames = state.commitFailedNames + fname }
                                    state.commitDoneCount++
                                }
                            }
                            state.committing = false; state.commitFinished = true
                            if (okCount > 0) reload(true)
                        }
                    }) { Text("执行") }
                }
            },
            dismissButton = { if (!running && !done) TextButton(onClick = { showConfirm = false; singleRenameRow = null }) { Text("取消") } }
        )
    }

    if (showSettings) SettingsDialog(state) { showSettings = false }
}

@Composable
fun CompactInput(value: String, onChange: (String) -> Unit, modifier: Modifier = Modifier,
                 placeholder: String = "", numeric: Boolean = false, heightDp: Int = 42,
                 onSearch: (() -> Unit)? = null) {
    var focused by remember { mutableStateOf(false) }
    BasicTextField(
        value = value, onValueChange = onChange, singleLine = true,
        textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface),
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(keyboardType = if (numeric) KeyboardType.Number else KeyboardType.Text,
            imeAction = if (onSearch != null) ImeAction.Search else ImeAction.Default),
        keyboardActions = KeyboardActions(onSearch = { onSearch?.invoke() }),
        modifier = modifier.height(heightDp.dp).clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(if (focused) 1.5.dp else 1.dp,
                if (focused) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                RoundedCornerShape(12.dp))
            .onFocusChanged { focused = it.isFocused },
        decorationBox = { inner ->
            Box(Modifier.fillMaxSize().padding(horizontal = 10.dp), contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty() && placeholder.isNotEmpty())
                    Text(placeholder, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                inner()
            }
        })
}

@Composable
fun LabeledInput(value: String, onChange: (String) -> Unit, label: String, modifier: Modifier = Modifier,
                 numeric: Boolean = false) {
    Column(modifier) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(3.dp))
        CompactInput(value, onChange, Modifier.fillMaxWidth(), numeric = numeric)
    }
}

/** New name with only the changed part in the accent color, the rest dimmed. */
fun diffAnnotated(old: String, new: String, base: Color, changed: Color): AnnotatedString {
    var pre = 0
    while (pre < minOf(old.length, new.length) && old[pre] == new[pre]) pre++
    var suf = 0
    while (suf < minOf(old.length - pre, new.length - pre) && old[old.length - 1 - suf] == new[new.length - 1 - suf]) suf++
    return buildAnnotatedString {
        withStyle(SpanStyle(color = base)) { append(new.substring(0, pre)) }
        withStyle(SpanStyle(color = changed, fontWeight = FontWeight.Bold)) { append(new.substring(pre, new.length - suf)) }
        withStyle(SpanStyle(color = base)) { append(new.substring(new.length - suf)) }
    }
}

@Composable
fun ToolsPanel(state: AppState, snackbar: SnackbarHostState) {
    val scope = rememberCoroutineScope()

    fun doSearch() {
        if (state.tmdbKeyword.isBlank() || state.tmdbSearching) return
        state.tmdbSearching = true
        scope.launch {
            try {
                val kw = state.tmdbKeyword.trim()
                val cacheKey = "${state.mediaType}_$kw"
                val cached = state.tmdbSearchCache[cacheKey]
                if (cached != null) {
                    state.tmdbResults = cached
                    if (cached.isEmpty()) snackbar.showSnackbar("没有搜到结果", duration = SnackbarDuration.Short)
                } else {
                    val raw = withContext(Dispatchers.IO) {
                        if (state.mediaType == "movie") {
                            // TVmaze has no movies: movies always go through TMDB
                            state.renamer!!.tmdbSearchMovie(kw, state.tmdbApiKey.trim()).first
                        } else when (state.scrapeSource) {
                            "tvmaze" -> tvmazeSearch(kw)
                            "tmdb" -> state.renamer!!.tmdbSearch(kw, state.tmdbApiKey.trim()).first
                            else -> try { state.renamer!!.tmdbSearch(kw, state.tmdbApiKey.trim()).first }
                                catch (e: Exception) { tvmazeSearch(kw) }
                        }
                    }
                    // TMDB ranks by popularity, so an unreleased sequel can outrank the
                    // exact title (e.g. 复仇者联盟5 above 复仇者联盟 2012): exact matches first.
                    val results = raw.sortedBy { if (it.name.trim() == kw) 0 else 1 }
                    state.tmdbSearchCache[cacheKey] = results
                    state.tmdbResults = results
                    if (results.isEmpty()) snackbar.showSnackbar("没有搜到结果", duration = SnackbarDuration.Short)
                }
            } catch (e: Exception) { snackbar.showSnackbar("搜索失败：${e.message}", duration = SnackbarDuration.Short) }
            state.tmdbSearching = false
        }
    }

    fun fetchSelectedEpisodes() {
        val res = state.tmdbSelected ?: return
        if (state.mediaType == "movie") {
            state.fillFromSelection()
            state.saveScrape()
            scope.launch { snackbar.showSnackbar("已填入电影名", duration = SnackbarDuration.Short) }
            return
        }
        state.tmdbFetching = true
        state.fillFromSelection()
        scope.launch {
            try {
                val season = state.tmdbSeason.toIntOrNull() ?: 1
                val key = "${state.scrapeSource}_${res.id}_$season"
                val cached = state.episodeCache[key]
                val eps = if (cached != null) cached else withContext(Dispatchers.IO) {
                    when (state.scrapeSource) {
                        "tvmaze" -> tvmazeEpisodes(res.id, season)
                        "tmdb" -> state.renamer!!.tmdbFetch(res.id, season, state.tmdbApiKey.trim()).first
                        else -> try { state.renamer!!.tmdbFetch(res.id, season, state.tmdbApiKey.trim()).first }
                            catch (e: Exception) {
                                val alt = tvmazeSearch(res.name).firstOrNull()
                                if (alt != null) tvmazeEpisodes(alt.id, season) else emptyMap()
                            }
                    }
                }
                if (cached == null) state.episodeCache[key] = eps
                state.tmdbEpisodes = eps
                state.fillFromSelection()
                state.saveScrape()
                snackbar.showSnackbar("已填入剧名和集名", duration = SnackbarDuration.Short)
            } catch (e: Exception) { snackbar.showSnackbar("获取集名失败：${e.message}", duration = SnackbarDuration.Short) }
            state.tmdbFetching = false
        }
    }

    // type-ahead: search 600ms after the user stops typing
    LaunchedEffect(state.tmdbKeyword) {
        val kw = state.tmdbKeyword.trim()
        if (kw.isEmpty()) return@LaunchedEffect
        delay(600)
        if (state.tmdbKeyword.trim() == kw) doSearch()
    }
    // type switched while a query is typed: re-search with the new type's endpoint
    // (otherwise the old type's results stay on screen, mislabeled as the new type)
    LaunchedEffect(state.mediaType) {
        if (state.tmdbKeyword.trim().isNotEmpty()) {
            state.tmdbSelected = null; state.tmdbEpisodes = emptyMap(); state.tmdbResults = emptyList()
            doSearch()
        }
    }
    // season changed while a show is selected: re-scrape that season automatically
    var lastSeason by remember { mutableStateOf(state.tmdbSeason) }
    LaunchedEffect(state.tmdbSeason) {
        if (state.mediaType == "tv" && state.tmdbSelected != null && state.tmdbSeason.isNotEmpty() && state.tmdbSeason != lastSeason) {
            delay(500)
            if (state.tmdbSeason != lastSeason) { lastSeason = state.tmdbSeason; fetchSelectedEpisodes() }
        } else { lastSeason = state.tmdbSeason }
    }
    Card(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 3.dp)) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // media type: TV series vs movie (Filmix-style split)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FilterChip(selected = state.mediaType == "tv",
                onClick = { state.mediaType = "tv"; state.dirMediaType[state.currentPath] = "tv"; state.tmdbSelected = null; state.tmdbEpisodes = emptyMap(); state.saveSetting() },
                label = { Text("剧集", style = MaterialTheme.typography.labelMedium) },
                leadingIcon = { Icon(Icons.Filled.Tv, null, Modifier.size(16.dp)) })
            FilterChip(selected = state.mediaType == "movie",
                onClick = { state.mediaType = "movie"; state.dirMediaType[state.currentPath] = "movie"; state.tmdbSelected = null; state.tmdbEpisodes = emptyMap(); state.saveSetting() },
                label = { Text("电影", style = MaterialTheme.typography.labelMedium) },
                leadingIcon = { Icon(Icons.Filled.Movie, null, Modifier.size(16.dp)) })
        }
        // numbering row
        if (state.mediaType == "tv")
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            LabeledInput(state.tmdbSeason, { state.tmdbSeason = it.filter { c -> c.isDigit() } }, "季", Modifier.weight(1f), numeric = true)
            LabeledInput(state.epStart, { state.epStart = it.filter { c -> c.isDigit() }; state.saveSetting() }, "起始集", Modifier.weight(1f), numeric = true)
            Button(onClick = { state.applyEpisodeNumbers(); scope.launch { snackbar.showSnackbar("已按顺序编号", duration = SnackbarDuration.Short) } },
                modifier = Modifier.height(42.dp), shape = RoundedCornerShape(50),
                contentPadding = PaddingValues(horizontal = 18.dp)) { Text("编号") }
        }
        // TMDB search row
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CompactInput(state.tmdbKeyword, { state.tmdbKeyword = it }, Modifier.weight(1f),
                placeholder = if (state.mediaType == "movie") "TMDB 搜索电影名" else "TMDB 搜索剧名", heightDp = 46, onSearch = { doSearch() })
            FilledIconButton(onClick = { doSearch() }, enabled = !state.tmdbSearching) {
                if (state.tmdbSearching) CircularProgressIndicator(Modifier.size(18.dp)) else Icon(Icons.Filled.Search, "搜索", Modifier.size(18.dp))
            }
        }
        if (state.tmdbResults.isNotEmpty()) {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(state.tmdbResults) { res ->
                    val selected = state.tmdbSelected?.id == res.id
                    Column(Modifier.width(80.dp).clickable {
                        state.tmdbSelected = res
                        fetchSelectedEpisodes()
                    }, horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(width = 70.dp, height = 104.dp).clip(RoundedCornerShape(12.dp))
                            .background(if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant)) {
                            if (res.poster.isNotEmpty()) PosterImage(res.poster)
                            else Icon(Icons.Filled.Movie, null, Modifier.align(Alignment.Center), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (selected) Icon(Icons.Filled.CheckCircle, null, Modifier.align(Alignment.TopEnd).size(16.dp),
                                tint = MaterialTheme.colorScheme.primary)
                        }
                        Text(res.name, style = MaterialTheme.typography.labelSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(res.year + if (state.mediaType == "movie") " · 电影" else " · 剧集",
                            style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        if (state.mediaType == "tv") Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(state.useEpisodeTitle, { state.useEpisodeTitle = it; state.saveSetting() }, modifier = Modifier.size(32.dp))
            Text("文件名包含集名", style = MaterialTheme.typography.bodySmall)
        }
        // media params
        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items(PRESETS) { p ->
                FilterChip(selected = state.mediaParams.contains(p),
                    onClick = { state.mediaParams = if (state.mediaParams.contains(p)) state.mediaParams - p else state.mediaParams + p },
                    label = { Text(p, style = MaterialTheme.typography.labelMedium) })
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            var custom by remember { mutableStateOf("") }
            CompactInput(custom, { custom = it }, Modifier.weight(1f), placeholder = "自定义参数", heightDp = 46)
            IconButton(onClick = { if (custom.isNotBlank()) { state.mediaParams = state.mediaParams + custom.trim(); custom = "" } }) {
                Icon(Icons.Filled.Add, "添加")
            }
            Button(onClick = { state.applyTags(); scope.launch { snackbar.showSnackbar("参数已应用到全部文件", duration = SnackbarDuration.Short) } },
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)) { Text("应用参数", style = MaterialTheme.typography.labelLarge) }
        }
        if (state.mediaParams.isNotEmpty()) {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                items(state.mediaParams) { p ->
                    InputChip(selected = true, onClick = { state.mediaParams = state.mediaParams - p },
                        label = { Text(p, style = MaterialTheme.typography.labelMedium) },
                        trailingIcon = { Icon(Icons.Filled.Close, null, Modifier.size(14.dp)) })
                }
            }
        }
    }
    }
}

private val posterCache = mutableMapOf<String, Bitmap>()

@Composable
fun PosterImage(path: String) {
    var bmp by remember(path) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(path) {
        bmp = posterCache[path] ?: withContext(Dispatchers.IO) {
            try {
                val conn = URL(path).openConnection() as HttpURLConnection
                conn.connectTimeout = 5000; conn.readTimeout = 5000
                conn.inputStream.use { BitmapFactory.decodeStream(it) }
            } catch (e: Exception) { null }
        }?.also { posterCache[path] = it }
    }
    if (bmp != null) androidx.compose.foundation.Image(bitmap = bmp!!.asImageBitmap(), contentDescription = null,
        modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDialog(state: AppState, onClose: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onClose, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp), containerColor = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.onSurface) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("关于", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            val ctx = LocalContext.current
            fun openUrl(u: String) { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(u))) }
            Text("OpenList 影视重命名 · v${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text("连接你的 OpenList，把杂乱的影视文件名一键改成 TMDB 标准格式。剧集按「剧名.S01E01.集名」命名，电影按「片名 (年份)」命名，改完直接在 Infuse、VidHub、Emby 里出海报墙。",
                style = MaterialTheme.typography.bodyMedium)
            Text("功能", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("· 剧集 / 电影两种模式，进目录自动识别，也可手动切换", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("· TMDB 搜索，点海报自动填入剧名与集名；TMDB 不行时自动换 TVmaze", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("· 批量编号、批量编辑，也支持单个文件搜索与重命名", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("· 媒体参数自动识别：分辨率、HDR、编码、音频、字幕语言", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("· 同名视频与字幕文件按集号合并，一起改名", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("· 目录缓存、按目录记住刮削结果，重复进目录不用重新加载", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text("作者", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("KoBariDev", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text("openlist-episode-renamer 的作者。平时折腾 NAS 与影视库，博客上有相关记录，GitHub 上有 10 个原创项目。",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("GitHub：github.com/KoBariDev", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clickable { openUrl("https://github.com/KoBariDev") })
                Text("博客：hub.131714.xyz", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clickable { openUrl("https://hub.131714.xyz") })
                Text("项目仓库：github.com/KoBariDev/openlist-episode-renamer", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clickable { openUrl("https://github.com/KoBariDev/openlist-episode-renamer") })
            }
        }
    }
}
