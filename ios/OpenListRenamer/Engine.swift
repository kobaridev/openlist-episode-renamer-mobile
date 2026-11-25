import Foundation

// MARK: - Constants

let defaultTmdbKey = "08a6bef260044f70c150251c79f2e476"
let mediaExtensions = ["mp4", "mkv", "avi", "ts", "flv", "wmv", "mov", "m4v", "webm", "mpg", "mpeg", "3gp", "asf", "srt", "ass", "ssa"]
let mediaPresets = ["1080p", "4K", "HDR", "HDR10", "DV", "DTS-HD", "中英字幕"]

let tmdbHeaders: [String: String] = [
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
]

// MARK: - Models

struct FsItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let isDir: Bool
    let size: Int64
    let path: String
}

struct EpisodeInfo {
    var title: String
    var season: String
    var episode: String
}

struct TmdbResult: Identifiable, Equatable {
    let id: Int
    let name: String
    let overview: String
    let year: String
    let poster: String
}

// MARK: - HTTP

enum HttpError: LocalizedError {
    case badStatus(Int)
    case badURL
    case noData

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "HTTP \(code)"
        case .badURL: return "地址无效"
        case .noData: return "没有返回数据"
        }
    }
}

struct Http {
    /// GET, throws on non-2xx. `timeout` defaults to 8s like the Android build.
    static func getText(_ urlString: String, headers: [String: String] = [:], timeout: TimeInterval = 8) async throws -> String {
        guard let url = URL(string: urlString) else { throw HttpError.badURL }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HttpError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// POST with a JSON body, returns the raw response text, throws on non-2xx.
    static func request(_ method: String, _ urlString: String, body: [String: Any]? = nil,
                        headers: [String: String] = [:], timeout: TimeInterval = 30) async throws -> String {
        guard let url = URL(string: urlString) else { throw HttpError.badURL }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Linux; Android 14) OpenListRenamer/1.0", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HttpError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - JSON helpers

typealias JSON = [String: Any]

func jsonObject(_ text: String) -> JSON? {
    guard let data = text.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? JSON else { return nil }
    return obj
}

func jsonArray(_ text: String) -> [JSON]? {
    guard let data = text.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [JSON] else { return nil }
    return arr
}

extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int { (self[key] as? NSNumber)?.intValue ?? 0 }
    func int64(_ key: String) -> Int64 { (self[key] as? NSNumber)?.int64Value ?? 0 }
    func string(_ key: String) -> String { self[key] as? String ?? "" }
    func bool(_ key: String) -> Bool { self[key] as? Bool ?? false }
    func object(_ key: String) -> JSON? { self[key] as? JSON }
    func array(_ key: String) -> [JSON] { self[key] as? [JSON] ?? [] }
}

// MARK: - Regex helpers

func regexMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> NSTextCheckingResult? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    return re.firstMatch(in: text, options: [], range: range)
}

func regexGroups(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
    guard let m = regexMatch(pattern, in: text, options: options) else { return nil }
    var out: [String] = []
    for i in 1..<m.numberOfRanges {
        let r = m.range(at: i)
        if r.location == NSNotFound { out.append("") }
        else if let swiftRange = Range(r, in: text) { out.append(String(text[swiftRange])) }
        else { out.append("") }
    }
    return out
}

func regexFindAll(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return re.matches(in: text, options: [], range: range).map { m in
        (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            if r.location == NSNotFound { return "" }
            if let swiftRange = Range(r, in: text) { return String(text[swiftRange]) }
            return ""
        }
    }
}

func cleanSeriesName(_ name: String) -> String {
    // Drop a trailing parenthesized note, e.g. "复仇者联盟 (2012)" -> "复仇者联盟".
    guard let re = try? NSRegularExpression(pattern: "\\s*[（(][^（）()]*[）)]", options: []) else { return name.trimmingCharacters(in: .whitespaces) }
    let range = NSRange(name.startIndex..., in: name)
    return re.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
}

// MARK: - OpenList client

final class Renamer {
    let baseUrlRaw: String
    let username: String
    let password: String
    var token: String?

    init(baseUrlRaw: String, username: String, password: String) {
        self.baseUrlRaw = baseUrlRaw
        self.username = username
        self.password = password
    }

    /// UserDefaults key for this account's saved token (matches Android).
    var tokenKey: String { "token_\(username)@\(base)" }

    private var base: String {
        baseUrlRaw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func login() async throws -> Bool {
        let text = try await Http.request("POST", "\(base)/api/auth/login",
                                         body: ["username": username, "password": password], timeout: 15)
        guard let obj = jsonObject(text), obj.int("code") == 200 else { return false }
        if let token = obj.object("data")?.string("token"), !token.isEmpty {
            self.token = token
            return true
        }
        return false
    }

    func validateCurrentUser() async -> Bool {
        guard let token = token else { return false }
        do {
            let text = try await Http.request("GET", "\(base)/api/me", headers: ["Authorization": token], timeout: 8)
            guard let obj = jsonObject(text), obj.int("code") == 200 else { return false }
            guard let data = obj.object("data") else { return true }
            let u = data.string("username")
            return u.isEmpty || u == username
        } catch {
            return false
        }
    }

    private func authHeaders() throws -> [String: String] {
        guard let token = token else { throw HttpError.noData }
        return ["Authorization": token]
    }

    func listContents(path: String) async throws -> [FsItem] {
        let text = try await Http.request("POST", "\(base)/api/fs/list",
                                         body: ["path": path, "password": "", "page": 1, "per_page": 0, "refresh": false],
                                         headers: try authHeaders())
        guard let obj = jsonObject(text) else { throw HttpError.noData }
        guard obj.int("code") == 200 else { throw NSError(domain: "OpenList", code: obj.int("code"), userInfo: [NSLocalizedDescriptionKey: obj.string("message").isEmpty ? "获取目录失败" : obj.string("message")]) }
        let content = obj.object("data")?.array("content") ?? []
        let basePath = path.hasSuffix("/") ? String(path.dropLast()) : path
        return content.compactMap { item in
            let name = item.string("name")
            guard !name.isEmpty else { return nil }
            return FsItem(name: name, isDir: item.bool("is_dir"), size: item.int64("size"),
                          path: basePath.isEmpty ? "/\(name)" : "\(basePath)/\(name)")
        }
    }

    func renameSingle(path: String, newName: String) async throws -> Bool {
        let text = try await Http.request("POST", "\(base)/api/fs/rename",
                                         body: ["path": path, "name": newName],
                                         headers: try authHeaders())
        guard let obj = jsonObject(text) else { return false }
        return obj.int("code") == 200
    }

    // MARK: SxxEyy parsing (port of core.py / Engine.kt)

    func extractEpisodeInfo(_ filename: String) -> EpisodeInfo {
        // Strict SxxEyy first: loose numeric patterns mistake years (1988, 2015) for season/episode.
        if let g = regexGroups(#"^(.+?)[\s._\-]*[Ss](\d{1,2})[\s._\-]*[Ee](\d{1,3})(?:\D|$)"#, in: filename), g.count >= 3 {
            var title = g[0].trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
            // Drop a trailing year wedged between the title and SxxEyy ("Reply 1988 2015" -> "Reply 1988").
            if let stripped = regexMatch(#"[\s._\-]+(19|20)\d{2}$"#, in: title) {
                let cut = title[..<title.index(title.startIndex, offsetBy: stripped.range.location)]
                let cleaned = String(cut).trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
                if !cleaned.isEmpty { title = cleaned }
            }
            if !title.isEmpty { return EpisodeInfo(title: title, season: g[1], episode: g[2]) }
        }
        let patterns = [
            #"(.+?)[\s._-]*S?(\d+)[\s._-]*E?(\d+)"#,
            #"(.+?)[\s._-]*(\d+)[\s._-]*(\d{2})"#,
            #"(.+?)[\s._-]*EP?[\s._-]*(\d+)"#,
            #"(.+?)[\s._-]*(\d+)[\s._-]*of[\s._-]*\d+"#
        ]
        for pattern in patterns {
            guard let g = regexGroups(pattern, in: filename, options: .caseInsensitive) else { continue }
            if g.count >= 2 {
                return EpisodeInfo(title: g[0].trimmingCharacters(in: CharacterSet(charactersIn: " ._-")),
                                   season: g[1], episode: g.count > 2 ? g[2] : g[1])
            } else if g.count >= 1 {
                return EpisodeInfo(title: g[0].trimmingCharacters(in: CharacterSet(charactersIn: " ._-")),
                                   season: "1", episode: g[0])
            }
        }
        let name = (filename as NSString).deletingPathExtension
        return EpisodeInfo(title: name, season: "1", episode: "1")
    }

    // MARK: TMDB (API first, scrape fallback)

    func tmdbApiSearch(keyword: String, apiKey: String) async throws -> [TmdbResult] {
        let q = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let text = try await Http.getText("https://api.themoviedb.org/3/search/tv?api_key=\(apiKey)&query=\(q)&language=zh-CN", timeout: 8)
        let results = jsonObject(text)?.array("results") ?? []
        return results.prefix(10).map { r in
            let posterPath = r.string("poster_path")
            return TmdbResult(id: r.int("id"),
                              name: cleanSeriesName(r.string("name")),
                              overview: String(r.string("overview").prefix(120)),
                              year: String(r.string("first_air_date").prefix(4)),
                              poster: (!posterPath.isEmpty && posterPath != "null") ? "https://image.tmdb.org/t/p/w185\(posterPath)" : "")
        }
    }

    func tmdbApiSeason(id: Int, season: Int, apiKey: String) async throws -> [String: String] {
        let text = try await Http.getText("https://api.themoviedb.org/3/tv/\(id)/season/\(season)?api_key=\(apiKey)&language=zh-CN", timeout: 8)
        var out: [String: String] = [:]
        for e in jsonObject(text)?.array("episodes") ?? [] {
            let name = e.string("name")
            if !name.isEmpty { out[String(e.int("episode_number"))] = name }
        }
        return out
    }

    func tmdbScrapeSearch(keyword: String) async throws -> [TmdbResult] {
        let q = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let html = try await Http.getText("https://www.themoviedb.org/search/tv?query=\(q)&language=zh-CN", headers: tmdbHeaders, timeout: 8)
        var out: [TmdbResult] = []
        var seen = Set<String>()
        let linkRe = #"href="/tv/(\d+)[^"]*"[^>]*>(?:(?!</a>).)*?<h2[^>]*>([^<]+)</h2>"#
        for m in regexFindAll(linkRe, in: html, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            let id = m[0]
            if seen.contains(id) { continue }
            seen.insert(id)
            out.append(TmdbResult(id: Int(id) ?? 0, name: cleanSeriesName(m[1].trimmingCharacters(in: .whitespaces)), overview: "", year: "", poster: ""))
            if out.count >= 10 { break }
        }
        if out.isEmpty {
            let altRe = #"href="/tv/(\d+)-[^"]*"[^>]*>\s*<img[^>]*alt="([^"]+)"#
            for m in regexFindAll(altRe, in: html, options: .caseInsensitive) {
                let id = m[0]
                if seen.contains(id) { continue }
                seen.insert(id)
                out.append(TmdbResult(id: Int(id) ?? 0, name: cleanSeriesName(m[1].trimmingCharacters(in: .whitespaces)), overview: "", year: "", poster: ""))
                if out.count >= 10 { break }
            }
        }
        return out
    }

    func tmdbScrapeSeason(id: Int, season: Int) async throws -> [String: String] {
        let html = try await Http.getText("https://www.themoviedb.org/tv/\(id)/season/\(season)?language=zh-CN", headers: tmdbHeaders, timeout: 8)
        var out: [String: String] = [:]
        let re = #"episode_number[^>]*>\s*(\d+)\s*<.*?episode_title[^>]*>.*?<a[^>]*>([^<]+)</a>"#
        for m in regexFindAll(re, in: html, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            out[m[0]] = m[1].trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    func tmdbApiSearchMovie(keyword: String, apiKey: String) async throws -> [TmdbResult] {
        let q = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let text = try await Http.getText("https://api.themoviedb.org/3/search/movie?api_key=\(apiKey)&query=\(q)&language=zh-CN", timeout: 8)
        let results = jsonObject(text)?.array("results") ?? []
        return results.prefix(10).map { r in
            let posterPath = r.string("poster_path")
            return TmdbResult(id: r.int("id"),
                              name: cleanSeriesName(r.string("title")),
                              overview: String(r.string("overview").prefix(120)),
                              year: String(r.string("release_date").prefix(4)),
                              poster: (!posterPath.isEmpty && posterPath != "null") ? "https://image.tmdb.org/t/p/w185\(posterPath)" : "")
        }
    }

    func tmdbSearchMovie(keyword: String, apiKey: String) async throws -> [TmdbResult] {
        if !apiKey.isEmpty {
            do { return try await tmdbApiSearchMovie(keyword: keyword, apiKey: apiKey) } catch { /* fallback */ }
        }
        let q = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let html = try await Http.getText("https://www.themoviedb.org/search/movie?query=\(q)&language=zh-CN", headers: tmdbHeaders, timeout: 8)
        var out: [TmdbResult] = []
        var seen = Set<String>()
        let linkRe = #"href="/movie/(\d+)[^"]*"[^>]*>(?:(?!</a>).)*?<h2[^>]*>([^<]+)</h2>"#
        for m in regexFindAll(linkRe, in: html, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            let id = m[0]
            if seen.contains(id) { continue }
            seen.insert(id)
            out.append(TmdbResult(id: Int(id) ?? 0, name: cleanSeriesName(m[1].trimmingCharacters(in: .whitespaces)), overview: "", year: "", poster: ""))
            if out.count >= 10 { break }
        }
        return out
    }

    func tmdbSearch(keyword: String, apiKey: String) async throws -> [TmdbResult] {
        if !apiKey.isEmpty {
            do { return try await tmdbApiSearch(keyword: keyword, apiKey: apiKey) } catch { /* fallback */ }
        }
        return try await tmdbScrapeSearch(keyword: keyword)
    }

    func tmdbFetch(id: Int, season: Int, apiKey: String) async throws -> [String: String] {
        if !apiKey.isEmpty {
            do { return try await tmdbApiSeason(id: id, season: season, apiKey: apiKey) } catch { /* fallback */ }
        }
        return try await tmdbScrapeSeason(id: id, season: season)
    }
}

// MARK: - TVmaze (free, no API key)

func tvmazeSearch(keyword: String) async throws -> [TmdbResult] {
    let q = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
    let text = try await Http.getText("https://api.tvmaze.com/search/shows?q=\(q)", timeout: 8)
    guard let arr = jsonArray(text) else { return [] }
    return arr.prefix(10).compactMap { item in
        guard let show = item.object("show") else { return nil }
        let summary = show.string("summary")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return TmdbResult(id: show.int("id"),
                          name: cleanSeriesName(show.string("name")),
                          overview: String(summary.prefix(120)),
                          year: String(show.string("premiered").prefix(4)),
                          poster: show.object("image")?.string("medium") ?? "")
    }
}

func tvmazeEpisodes(id: Int, season: Int) async throws -> [String: String] {
    let text = try await Http.getText("https://api.tvmaze.com/shows/\(id)/episodes", timeout: 8)
    guard let arr = jsonArray(text) else { return [:] }
    var out: [String: String] = [:]
    for e in arr where e.int("season") == season {
        let name = e.string("name")
        if !name.isEmpty { out[String(e.int("number"))] = name }
    }
    return out
}

// MARK: - Media tag detection from the release filename

func detectMediaParams(_ filename: String) -> [String] {
    let u = filename.uppercased()
    var out: [String] = []
    func has(_ pats: String...) -> Bool { pats.contains { u.contains($0) } }
    if has("2160P") || regexMatch(#"(^|[\s._-])4K([\s._-]|$)"#, in: u) != nil { out.append("4K") }
    else if has("1080P") { out.append("1080p") }
    else if has("720P") { out.append("720p") }
    else if has("480P") { out.append("480p") }
    if has("HDR10+") { out.append("HDR10+") }
    else if has("HDR10") { out.append("HDR10") }
    else if has("DOLBY VISION") || regexMatch(#"(^|[\s._-])DV([\s._-]|$)"#, in: u) != nil { out.append("DV") }
    else if has("HDR") { out.append("HDR") }
    if has("X265", "HEVC", "H.265", "H265") { out.append("HEVC") }
    else if has("X264", "H.264", "H264", "AVC") { out.append("H.264") }
    else if has("VP9") { out.append("VP9") }
    else if has("AV1") { out.append("AV1") }
    if has("DTS-HD", "DTSHD") { out.append("DTS-HD") }
    else if has("TRUEHD") { out.append("TrueHD") }
    else if has("ATMOS") { out.append("Atmos") }
    else if has("DTS") { out.append("DTS") }
    else if has("EAC3", "DD+", "DDP") { out.append("DD+") }
    else if has("AC3") { out.append("AC3") }
    else if has("AAC") { out.append("AAC") }
    else if has("FLAC") { out.append("FLAC") }
    if has("中英", "中英字幕", "中英双字", "中英双语") { out.append("中英字幕") }
    else if has("中字", "简中", "繁中") { out.append("中字") }
    else if has("国语", "国配") { out.append("国语") }
    else if has("粤语") { out.append("粤语") }
    return out
}

// MARK: - Shared helpers

func pad2(_ n: String) -> String {
    let s = n.isEmpty ? "0" : n
    return s.count >= 2 ? s : "0" + s
}

func parentOf(_ p: String) -> String {
    var t = p
    while t.hasSuffix("/") { t.removeLast() }
    guard let i = t.lastIndex(of: "/") else { return "/" }
    if i <= t.startIndex { return "/" }
    return String(t[..<i])
}

func dirNameOf(_ p: String) -> String {
    p.split(separator: "/").filter { !$0.isEmpty }.last.map(String.init) ?? ""
}

func natCmp(_ a: String, _ b: String) -> Bool {
    // Natural-order "less than": numeric chunks compare numerically.
    func chunks(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var curIsDigit: Bool? = nil
        for ch in s.lowercased() {
            let d = ch.isNumber
            if curIsDigit == nil || curIsDigit == d { cur.append(ch) }
            else { out.append(cur); cur = String(ch) }
            curIsDigit = d
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
    let ra = chunks(a), rb = chunks(b)
    for i in 0..<min(ra.count, rb.count) {
        let x = ra[i], y = rb[i]
        if x == y { continue }
        if let xi = Int(x), let yi = Int(y) { return xi < yi }
        return x < y
    }
    return ra.count < rb.count
}

func isMediaFile(_ name: String) -> Bool {
    let ext = (name as NSString).pathExtension.lowercased()
    return mediaExtensions.contains(ext)
}

/// Common prefix/suffix diff: returns (prefix, changed, suffix) of `new` against `old`.
func diffParts(old: String, new: String) -> (String, String, String) {
    var pre = 0
    let oldChars = Array(old), newChars = Array(new)
    while pre < min(oldChars.count, newChars.count) && oldChars[pre] == newChars[pre] { pre += 1 }
    var suf = 0
    while suf < min(oldChars.count - pre, newChars.count - pre)
            && oldChars[oldChars.count - 1 - suf] == newChars[newChars.count - 1 - suf] { suf += 1 }
    let prefix = String(newChars[0..<pre])
    let middle = String(newChars[pre..<(newChars.count - suf)])
    let suffix = String(newChars[(newChars.count - suf)...])
    return (prefix, middle, suffix)
}
