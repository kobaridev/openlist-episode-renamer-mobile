import SwiftUI

// MARK: - One file (a video + its same-name subtitles) in the list

final class RowState: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    var names: [String]
    @Published var valid: Bool
    @Published var title: String
    @Published var season: String
    @Published var episode: String
    @Published var epTitle: String = ""
    @Published var year: String = ""
    @Published var tags: String = ""

    init(name: String, valid: Bool, info: EpisodeInfo) {
        self.name = name
        self.names = [name]
        self.valid = valid
        self.title = info.title
        self.season = info.season
        self.episode = info.episode
    }
}

// MARK: - App state (port of Android AppState)

@MainActor
final class AppState: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var renamer: Renamer?
    @Published var loggedIn = false
    @Published var loading = false
    @Published var loadError = ""
    @Published var committing = false
    @Published var currentPath = "/"
    @Published var directories: [FsItem] = []
    @Published var files: [FsItem] = []
    @Published var rows: [RowState] = []
    @Published var user = ""
    @Published var openlistOk = false
    @Published var editingRow: RowState?
    @Published var toolsOpen = false
    @Published var selected: Set<String> = []
    @Published var batchOpen = false

    @Published var scrapeSource: String
    @Published var tmdbApiKey: String
    @Published var delimiter: String
    @Published var useEpisodeTitle: Bool
    @Published var defaultSeason: String
    @Published var epStart: String
    @Published var darkTheme: Bool

    @Published var mediaType: String
    @Published var tmdbKeyword = ""
    @Published var tmdbSeason: String
    @Published var tmdbResults: [TmdbResult] = []
    @Published var tmdbSelected: TmdbResult?
    @Published var tmdbEpisodes: [String: String] = [:]
    @Published var tmdbSearching = false
    @Published var tmdbFetching = false
    @Published var mediaParams: [String] = []

    @Published var commitTotal = 0
    @Published var commitDoneCount = 0
    @Published var commitFailedNames: [String] = []
    @Published var commitFinished = false

    @Published var toast: String?

    /// Short toast (Android snackbar equivalent), auto-dismissed after 2s.
    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == message { toast = nil }
        }
    }

    // In-memory caches (not persisted, like the Android build).
    var dirCache: [String: (dirs: [FsItem], files: [FsItem], rows: [RowState])] = [:]
    var dirScrape: [String: (sel: TmdbResult, season: String, episodes: [String: String])] = [:]
    var dirMediaType: [String: String] = [:]
    var tmdbSearchCache: [String: [TmdbResult]] = [:]
    var episodeCache: [String: [String: String]] = [:]

    init() {
        scrapeSource = defaults.string(forKey: "scrape_source") ?? "auto"
        tmdbApiKey = defaults.string(forKey: "tmdb_api_key") ?? defaultTmdbKey
        delimiter = defaults.string(forKey: "delimiter") ?? "."
        useEpisodeTitle = defaults.object(forKey: "use_episode_title") as? Bool ?? true
        defaultSeason = defaults.string(forKey: "default_season") ?? "1"
        epStart = defaults.string(forKey: "default_episode_start") ?? "1"
        darkTheme = (defaults.string(forKey: "theme") ?? "light") == "dark"
        mediaType = defaults.string(forKey: "media_type") ?? "tv"
        tmdbSeason = defaults.string(forKey: "default_season") ?? "1"
    }

    func saveSetting() {
        defaults.set(mediaType, forKey: "media_type")
        defaults.set(scrapeSource, forKey: "scrape_source")
        defaults.set(tmdbApiKey, forKey: "tmdb_api_key")
        defaults.set(delimiter, forKey: "delimiter")
        defaults.set(useEpisodeTitle, forKey: "use_episode_title")
        defaults.set(defaultSeason, forKey: "default_season")
        defaults.set(epStart, forKey: "default_episode_start")
        defaults.set(darkTheme ? "dark" : "light", forKey: "theme")
    }

    // MARK: Preview names

    func previewName(_ r: RowState) -> String {
        let d = delimiter.isEmpty ? "." : delimiter
        let title = r.title.isEmpty ? "UNKNOWN" : r.title
        let ext = (r.name as NSString).pathExtension
        let extSuffix = ext.isEmpty ? "" : ".\(ext)"
        if mediaType == "movie" {
            var name = title
            if !r.year.isEmpty { name += " (\(r.year.trimmingCharacters(in: .whitespaces)))" }
            let parts = r.tags.split { ",，;；|".contains($0) }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !parts.isEmpty { name += d + parts.joined(separator: d) }
            return name + extSuffix
        }
        var name = title + d + "S" + pad2(r.season) + "E" + pad2(r.episode)
        if useEpisodeTitle && !r.epTitle.isEmpty { name += d + r.epTitle.trimmingCharacters(in: .whitespaces) }
        let parts = r.tags.split { ",，;；|".contains($0) }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !parts.isEmpty { name += d + parts.joined(separator: d) }
        return name + extSuffix
    }

    func previewBase(_ r: RowState) -> String {
        let full = previewName(r)
        return (full as NSString).deletingPathExtension
    }

    var renameableCount: Int { rows.filter { previewName($0) != $0.name }.count }

    // MARK: S/E anchor sync (TV only; movies are each their own title)

    func syncEpisodes() {
        guard mediaType != "movie" else { return }
        var baseCount: [String: Int] = [:]
        for r in rows {
            let b = (r.name as NSString).deletingPathExtension.lowercased()
            baseCount[b, default: 0] += 1
        }
        var groups: [String: [Int]] = [:]
        for (i, r) in rows.enumerated() {
            let b = (r.name as NSString).deletingPathExtension.lowercased()
            let key: String
            if (baseCount[b] ?? 0) > 1 {
                key = "b\(b)"
            } else {
                let s = pad2(r.season), e = pad2(r.episode)
                key = (s != "00" && e != "00" && !s.isEmpty && !e.isEmpty) ? "s\(s)e\(e)" : "b\(b)"
            }
            groups[key, default: []].append(i)
        }
        for g in groups.values where g.count >= 2 {
            let anchor = rows[g[0]]
            let titled = g.map { rows[$0] }.first { !$0.epTitle.isEmpty }
            for i in g {
                let r = rows[i]
                r.title = anchor.title
                r.season = anchor.season
                r.episode = anchor.episode
                r.tags = anchor.tags
                if let titled = titled, titled !== r { r.epTitle = titled.epTitle }
            }
        }
    }

    func applyEpisodeNumbers() {
        guard !rows.isEmpty else { return }
        let season = tmdbSeason.isEmpty ? "1" : tmdbSeason
        var ep = Int(epStart) ?? 1
        var groups: [String] = []
        var seen = Set<String>()
        for r in rows {
            let key = (r.name as NSString).deletingPathExtension.lowercased()
            if seen.insert(key).inserted { groups.append(key) }
        }
        for key in groups {
            for r in rows where (r.name as NSString).deletingPathExtension.lowercased() == key {
                r.season = season
                r.episode = String(ep)
            }
            ep += 1
        }
        syncEpisodes()
    }

    func fillFromSelection() {
        guard let sel = tmdbSelected else { return }
        if mediaType == "movie" {
            for r in rows { r.title = sel.name; r.year = sel.year }
            syncEpisodes()
            return
        }
        var n = 0
        for r in rows {
            r.title = sel.name
            if r.season.isEmpty { r.season = tmdbSeason.isEmpty ? "1" : tmdbSeason }
            let ep = Int(r.episode) ?? ((Int(epStart) ?? 1) + n)
            r.episode = String(ep)
            if useEpisodeTitle, let t = tmdbEpisodes[String(ep)] { r.epTitle = t.trimmingCharacters(in: .whitespaces) }
            n += 1
        }
        syncEpisodes()
    }

    func applyTags() {
        let joined = mediaParams.joined(separator: ",")
        for r in rows { r.tags = joined }
        syncEpisodes()
    }

    // MARK: Per-directory scrape memory

    func saveScrape() {
        if let sel = tmdbSelected {
            dirScrape[currentPath] = (sel: sel, season: tmdbSeason, episodes: tmdbEpisodes)
        }
        dirMediaType[currentPath] = mediaType
    }

    func restoreScrape() {
        if let type = dirMediaType[currentPath] { mediaType = type }
        if let saved = dirScrape[currentPath] {
            tmdbSelected = saved.sel
            tmdbSeason = saved.season
            tmdbEpisodes = saved.episodes
            fillFromSelection()
        }
    }

    // MARK: Token persistence

    func loadToken(_ r: Renamer) {
        r.token = defaults.string(forKey: r.tokenKey)
    }

    func saveToken(_ r: Renamer) {
        if let token = r.token {
            defaults.set(token, forKey: r.tokenKey)
        }
    }

    // MARK: Directory loading

    func loadDir(force: Bool = false) async throws {
        guard let r = renamer else { return }
        if !force, let cached = dirCache[currentPath] {
            directories = cached.dirs
            files = cached.files
            rows = cached.rows
            openlistOk = true
            loadError = ""
            loading = false
            if dirMediaType[currentPath] == nil {
                mediaType = files.contains { regexMatch(#"(?i)S\d{1,2}[\s._\-]*E\d{1,3}"#, in: $0.name) != nil } ? "tv" : "movie"
            }
            restoreScrape()
            return
        }
        loading = true
        loadError = ""
        defer { loading = false }
        var items: [FsItem]?
        do {
            items = try await r.listContents(path: currentPath)
        } catch {
            // Only an auth-looking failure earns a re-login + retry.
            let msg = (error.localizedDescription).lowercased()
            let authLike = msg.contains("token") || msg.contains("401") || msg.contains("unauthorized") || msg.contains("登录") || msg.contains("invalid")
            if authLike, await relogin(), let r2 = renamer {
                items = try await r2.listContents(path: currentPath)
            } else {
                openlistOk = false
                loadError = error.localizedDescription
                throw error
            }
        }
        let list = items ?? []
        directories = list.filter { $0.isDir }.sorted { natCmp($0.name, $1.name) }
        files = list.filter { !$0.isDir }.sorted { natCmp($0.name, $1.name) }
        func extPri(_ name: String) -> Int {
            switch (name as NSString).pathExtension.lowercased() {
            case "mp4", "mkv", "avi", "ts", "mov", "webm", "flv", "wmv", "m4v", "mpg", "mpeg": return 0
            case "srt", "ass", "ssa", "vtt": return 1
            default: return 2
            }
        }
        // Group by parsed season/episode, not by filename: a subtitle and its video often
        // carry different release tags, but they are the same episode.
        let parsed: [(FsItem, EpisodeInfo)] = files.map { ($0, r.extractEpisodeInfo($0.name)) }
        var groups: [String: [(FsItem, EpisodeInfo)]] = [:]
        for (f, info) in parsed {
            let sn = Int(info.season), ep = Int(info.episode)
            let key: String
            if regexMatch(#"(?i)S\d{1,2}[\s._\-]*E\d{1,3}"#, in: f.name) != nil, let sn = sn, let ep = ep {
                key = "se_\(sn)_\(ep)"
            } else {
                key = "base_" + (f.name as NSString).deletingPathExtension.lowercased()
            }
            groups[key, default: []].append((f, info))
        }
        rows = groups.values.map { g in
            let sorted = g.sorted {
                let c = extPri($0.0.name) - extPri($1.0.name)
                if c != 0 { return c < 0 }
                return natCmp($0.0.name, $1.0.name)
            }
            let (main, info) = sorted[0]
            let row = RowState(name: main.name, valid: true, info: info)
            row.names = sorted.map { $0.0.name }
            row.tags = detectMediaParams(main.name).joined(separator: ",")
            return row
        }.sorted {
            let sa = Int($0.season) ?? 999, sb = Int($1.season) ?? 999
            if sa != sb { return sa < sb }
            let ea = Int($0.episode) ?? 99999, eb = Int($1.episode) ?? 99999
            if ea != eb { return ea < eb }
            return natCmp($0.name, $1.name)
        }
        openlistOk = true
        selected = []
        dirCache[currentPath] = (dirs: directories, files: files, rows: rows)
        if dirMediaType[currentPath] == nil {
            mediaType = files.contains { regexMatch(#"(?i)S\d{1,2}[\s._\-]*E\d{1,3}"#, in: $0.name) != nil } ? "tv" : "movie"
        }
        restoreScrape()
    }

    func relogin() async -> Bool {
        guard let old = renamer else { return false }
        let r = Renamer(baseUrlRaw: old.baseUrlRaw, username: old.username, password: old.password)
        do {
            if try await r.login() {
                saveToken(r)
                renamer = r
                return true
            }
        } catch { /* fall through */ }
        return false
    }

    /// Returns an error message on failure, nil on success. Mirrors Android doLogin.
    func doLogin(base: String, user: String, pass: String) async -> String? {
        var b = base.trimmingCharacters(in: .whitespaces)
        if b.isEmpty { b = "http://127.0.0.1:5244" }
        if !b.hasPrefix("http://") && !b.hasPrefix("https://") {
            let host = b.split(whereSeparator: { $0 == "/" || $0 == ":" }).first.map(String.init)?.lowercased() ?? ""
            let ipv4 = regexMatch(#"^\d{1,3}(\.\d{1,3}){3}$"#, in: host) != nil
            let useHttp = host == "127.0.0.1" || host == "localhost" || host.hasSuffix(".internal") || ipv4
            b = (useHttp ? "http://" : "https://") + b
        }
        // Try the primary scheme first, then the other one: the scheme guess
        // is often wrong for self-hosted servers (e.g. a public hostname
        // serving plain http, or an https-only host typed as http).
        var candidates = [b]
        if b.hasPrefix("http://") { candidates.append("https://" + String(b.dropFirst("http://".count))) }
        else if b.hasPrefix("https://") { candidates.append("http://" + String(b.dropFirst("https://".count))) }
        var lastError: String?
        for cand in candidates {
            let r = Renamer(baseUrlRaw: cand, username: user, password: pass)
            loadToken(r)
            if r.token != nil, await r.validateCurrentUser() {
                return succeedLogin(r, base: cand, user: user, pass: pass)
            }
            do {
                if try await r.login() {
                    return succeedLogin(r, base: cand, user: user, pass: pass)
                }
                // Server answered but credentials were rejected: the scheme
                // is right, retrying the other one cannot help.
                return "登录失败，请检查账号密码"
            } catch {
                // Network-level failure: remember it and try the other scheme.
                lastError = friendlyError(error)
            }
        }
        return lastError ?? "登录失败，请检查账号密码"
    }

    /// Shared success path for doLogin: persist the working base URL + token.
    private func succeedLogin(_ r: Renamer, base: String, user: String, pass: String) -> String? {
        saveToken(r)
        renamer = r
        self.user = user
        openlistOk = true
        loggedIn = true
        defaults.set(base, forKey: "base_url")
        defaults.set(user, forKey: "username")
        defaults.set(pass, forKey: "password")
        return nil
    }

    /// Turn a URLSession failure into a message that says what actually broke.
    private func friendlyError(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .appTransportSecurityRequiresSecureConnection:
            return "iOS 拦截了 http 连接：请更新到最新版，或把地址改成 https://"
        case .cannotConnectToHost, .cannotFindHost:
            return "连不上服务器：检查地址对不对、服务器有没有在跑"
        case .timedOut:
            return "连接超时：服务器没响应，检查地址和网络"
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateNotYetValid:
            return "https 证书有问题：试试把地址改成 http://"
        case .notConnectedToInternet:
            return "iPad 没有联网"
        default:
            return urlError.localizedDescription
        }
    }
}

// MARK: - App entry

@main
struct OpenListRenamerApp: App {
    @StateObject private var store = AppState()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.pageGradient(dark: store.darkTheme).ignoresSafeArea()
                if store.loggedIn {
                    MainView().environmentObject(store)
                } else {
                    LoginView().environmentObject(store)
                }
            }
            .preferredColorScheme(store.darkTheme ? .dark : .light)
        }
    }
}
