import SwiftUI

// MARK: - Main screen (port of Android MainScreen)

struct MainView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showAbout = false
    @State private var showConfirm = false
    @State private var singleRenameRow: RowState?
    @State private var renameDirTarget: FsItem?
    @State private var dirRenameText = ""

    private var isWide: Bool { sizeClass == .regular }

    private var confirmChanges: [RowState] {
        if let single = singleRenameRow { return [single] }
        if !store.selected.isEmpty {
            return store.rows.filter { store.selected.contains($0.name) && store.previewName($0) != $0.name }
        }
        return store.rows.filter { store.previewName($0) != $0.name }
    }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: geo.safeAreaInsets.top)
                        header
                        breadcrumbs
                        toolsToggle
                        if store.toolsOpen {
                            ToolsPanel()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }
                        directories
                        statusViews
                        fileRows
                    }
                    .frame(width: contentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 185)
                }
                bottomBars
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                if store.loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.top, 4)
                }
                if let toast = store.toast {
                    Text(toast)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.label).opacity(0.85))
                        .foregroundColor(Color(.systemBackground))
                        .clipShape(Capsule())
                        .padding(.bottom, 140)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task { await reload() }
        .onChange(of: store.currentPath) { _ in store.toolsOpen = false }
        .sheet(item: $store.editingRow) { row in
            EditSheet(row: row) {
                singleRenameRow = row
                store.editingRow = nil
                showConfirm = true
            }
        }
        .sheet(isPresented: $store.batchOpen) { BatchSheet() }
        .sheet(isPresented: $showConfirm) {
            ConfirmRenameView(changes: confirmChanges) {
                showConfirm = false
                singleRenameRow = nil
            }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .alert("重命名目录", isPresented: Binding(
            get: { renameDirTarget != nil },
            set: { if !$0 { renameDirTarget = nil } }
        )) {
            TextField("新名称", text: $dirRenameText)
            Button("确定") { Task { await renameDirectory() } }
            Button("取消", role: .cancel) { renameDirTarget = nil }
        }
    }

    // MARK: Header

    private var header: some View {
        Text(dirNameOf(store.currentPath).isEmpty ? "根目录" : dirNameOf(store.currentPath))
            .font(.title2)
            .bold()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
    }

    // MARK: Breadcrumbs

    private var breadcrumbs: some View {
        let parts = store.currentPath.split(separator: "/").filter { !$0.isEmpty }.map(String.init)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button(action: { store.currentPath = "/"; Task { await reload() } }) {
                    Label("/", systemImage: "house.fill")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    Button(action: {
                        store.currentPath = "/" + parts[0...i].joined(separator: "/")
                        Task { await reload() }
                    }) {
                        Text(part)
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: Tools toggle pill

    private var toolsToggle: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.3)) { store.toolsOpen.toggle() } }) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                Text(store.toolsOpen ? "收起批量工具" : "批量工具 · TMDB · 集名刮削 · 编号 · 参数")
                    .font(.headline)
                    .bold()
                Image(systemName: store.toolsOpen ? "chevron.up" : "chevron.down")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(store.toolsOpen ? Color(.systemBackground) : Color.appPrimary)
            .foregroundColor(store.toolsOpen ? Color.appPrimary : .white)
            .clipShape(Capsule())
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: Directory cards

    private var directories: some View {
        ForEach(store.directories) { dir in
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.appContainer)
                        .frame(width: 40, height: 40)
                    Image(systemName: "folder.fill")
                        .foregroundColor(.appPrimary)
                        .font(.system(size: 20))
                }
                Text(dir.name)
                    .font(.body)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: { renameDirTarget = dir; dirRenameText = dir.name }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            .contentShape(Rectangle())
            .onTapGesture {
                store.currentPath = store.currentPath == "/" ? "/\(dir.name)" : "\(store.currentPath)/\(dir.name)"
                Task { await reload() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
    }

    // MARK: Error / empty states

    @ViewBuilder
    private var statusViews: some View {
        if !store.loadError.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "icloud.slash")
                    .foregroundColor(.red)
                    .font(.system(size: 32))
                Text("目录加载失败").bold()
                Text(store.loadError).font(.subheadline).foregroundColor(.red)
                Button("重试") { Task { await reload() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        if !store.loading && store.loadError.isEmpty && store.rows.isEmpty {
            Text("当前目录没有可重命名的媒体文件")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    // MARK: File rows

    private var fileRows: some View {
        ForEach(store.rows) { row in
            FileRowView(row: row)
        }
    }

    // MARK: Bottom bars

    private var bottomBars: some View {
        VStack(spacing: 8) {
            // Action bar
            HStack(spacing: 8) {
                if !store.selected.isEmpty {
                    Text("已选 \(store.selected.count)")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.appPrimary)
                    Button("全选") { store.selected = Set(store.rows.map { $0.name }) }
                    Button("取消") { store.selected = [] }
                    Spacer()
                    Button(action: { store.batchOpen = true }) {
                        Label("批量编辑", systemImage: "pencil")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    Button(action: { showConfirm = true }) {
                        Label("重命名", systemImage: "square.and.pencil")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!store.rows.contains { store.selected.contains($0.name) && store.previewName($0) != $0.name } || store.committing)
                } else {
                    Text("\(store.rows.count) 文件 · \(store.renameableCount) 待改")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { if store.renameableCount > 0 { showConfirm = true } }) {
                        Label("重命名", systemImage: "square.and.pencil")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(store.renameableCount == 0 || store.committing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground).opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(radius: 8)

            // Nav pill
            HStack(spacing: 4) {
                navButton("house.fill", "根目录") {
                    store.currentPath = "/"; Task { await reload() }
                }
                navButton("arrow.backward", "上级目录", disabled: store.currentPath == "/") {
                    store.currentPath = parentOf(store.currentPath); Task { await reload() }
                }
                navButton("arrow.clockwise", "刷新") { Task { await reload(force: true) } }
                navButton(store.darkTheme ? "sun.max.fill" : "moon.fill", "主题") {
                    store.darkTheme.toggle(); store.saveSetting()
                }
                navButton("info.circle", "关于") { showAbout = true }
                navButton("rectangle.portrait.and.arrow.right", "退出") {
                    UserDefaults.standard.removeObject(forKey: "password")
                    store.renamer = nil
                    store.loggedIn = false
                    store.rows = []
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemBackground).opacity(0.96))
            .clipShape(Capsule())
            .shadow(radius: 10)
        }
    }

    private func navButton(_ image: String, _ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 20))
                .frame(width: 44, height: 40)
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    // MARK: Actions

    func reload(force: Bool = false) async {
        do {
            try await store.loadDir(force: force)
        } catch {
            store.showToast("加载失败：\(store.loadError.isEmpty ? error.localizedDescription : store.loadError)")
        }
    }

    private func renameDirectory() async {
        guard let target = renameDirTarget else { return }
        let newName = dirRenameText.trimmingCharacters(in: .whitespaces)
        renameDirTarget = nil
        guard !newName.isEmpty, newName != target.name, let ren = store.renamer else { return }
        do {
            if try await ren.renameSingle(path: target.path, newName: newName) {
                store.dirCache.removeAll()
                store.showToast("目录已重命名")
                await reload(force: true)
            }
        } catch {
            store.showToast("重命名失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - One file row (原名 / 新名，差异高亮）

struct FileRowView: View {
    @EnvironmentObject var store: AppState
    @ObservedObject var row: RowState

    var body: some View {
        let preview = store.previewName(row)
        let changed = preview != row.name
        let checked = store.selected.contains(row.name)
        let groupNote = row.names.count > 1 ? " · 同名 \(row.names.count) 个" : ""
        return HStack(spacing: 0) {
            Button(action: {
                if checked { store.selected.remove(row.name) } else { store.selected.insert(row.name) }
            }) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(checked ? .appPrimary : .secondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("原名").font(.caption).foregroundColor(.secondary)
                        Text(row.name)
                            .font(.body)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if store.mediaType == "movie" {
                            if !row.year.isEmpty {
                                Text(row.year)
                                    .font(.caption).bold()
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.appContainer)
                                    .foregroundColor(Color(hex: 0x041E49))
                                    .clipShape(Capsule())
                            }
                        } else {
                            Text("S\(pad2(row.season))E\(pad2(row.episode))")
                                .font(.caption).bold()
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.appContainer)
                                .foregroundColor(Color(hex: 0x041E49))
                                .clipShape(Capsule())
                        }
                    }
                    if changed {
                        HStack(spacing: 4) {
                            Text("新名").font(.caption).bold().foregroundColor(.appPrimary)
                            DiffText(old: row.name, new: preview)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(groupNote).font(.subheadline).foregroundColor(.secondary)
                        }
                    } else {
                        Text("未修改" + groupNote)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.trailing, 12)
            .background(checked ? Color.appContainer.opacity(0.45) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(checked ? Color.appPrimary : Color(.systemGray5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            .contentShape(Rectangle())
            .onTapGesture { store.editingRow = row }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
    }
}

// MARK: - Search results (vertical list, same as Android: thumb + title + year)

struct PosterResultsView: View {
    @EnvironmentObject var store: AppState
    let results: [TmdbResult]
    let selectedId: Int?
    let onTap: (TmdbResult) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(results) { res in
                let selected = selectedId == res.id
                Button(action: { onTap(res) }) {
                    HStack(spacing: 12) {
                        PosterImage(urlString: res.poster)
                            .frame(width: 56, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(res.name)
                                .font(.subheadline)
                                .bold(selected)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(res.year + (store.mediaType == "movie" ? " · 电影" : " · 剧集"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if !res.overview.isEmpty {
                                Text(res.overview)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.appPrimary)
                                .font(.system(size: 22))
                        }
                    }
                    .padding(8)
                    .background(selected ? Color.appContainer : Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? Color.appPrimary : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Batch tools panel (port of Android ToolsPanel)

struct ToolsPanel: View {
    @EnvironmentObject var store: AppState
    @State private var searchTask: Task<Void, Never>?

    @State private var seasonTask: Task<Void, Never>?
    @State private var customParam = ""

    var body: some View {
        VStack(spacing: 10) {
            // Media type: TV series vs movie
            HStack(spacing: 8) {
                TypeChip(title: "剧集", systemImage: "tv", selected: store.mediaType == "tv") {
                    switchType("tv")
                }
                TypeChip(title: "电影", systemImage: "film", selected: store.mediaType == "movie") {
                    switchType("movie")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Numbering row (TV only)
            if store.mediaType == "tv" {
                HStack(spacing: 8) {
                    LabeledField(text: $store.tmdbSeason, label: "季", numeric: true)
                    LabeledField(text: $store.epStart, label: "起始集", numeric: true)
                    Button("编号") {
                        store.applyEpisodeNumbers()
                        store.showToast("已按顺序编号")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .frame(height: 46)
                }
            }

            // TMDB search row
            HStack(spacing: 6) {
                CompactField(text: $store.tmdbKeyword,
                             placeholder: store.mediaType == "movie" ? "TMDB 搜索电影名" : "TMDB 搜索剧名",
                             height: 48) { Task { await doSearch() } }
                Button(action: { Task { await doSearch() } }) {
                    Group {
                        if store.tmdbSearching {
                            ProgressView().frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "magnifyingglass").font(.system(size: 18))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(Color.appPrimary)
                    .foregroundColor(.white)
                    .clipShape(Circle())
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(store.tmdbSearching)
            }

            if !store.tmdbResults.isEmpty {
                PosterResultsView(results: store.tmdbResults, selectedId: store.tmdbSelected?.id) { res in
                    store.tmdbSelected = res
                    Task { await fetchSelectedEpisodes() }
                }
            }

            if store.mediaType == "tv" {
                Toggle("文件名包含集名", isOn: $store.useEpisodeTitle)
                    .onChange(of: store.useEpisodeTitle) { _ in store.saveSetting() }
            }

            // Media params
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(mediaPresets, id: \.self) { preset in
                        let on = store.mediaParams.contains(preset)
                        Button(preset) {
                            if on { store.mediaParams.removeAll { $0 == preset } }
                            else { store.mediaParams.append(preset) }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(on ? Color.appPrimary : Color(.systemGray5))
                        .foregroundColor(on ? .white : .primary)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 6) {
                CompactField(text: $customParam, placeholder: "自定义参数", height: 48)
                Button(action: {
                    if !customParam.trimmingCharacters(in: .whitespaces).isEmpty {
                        store.mediaParams.append(customParam.trimmingCharacters(in: .whitespaces))
                        customParam = ""
                    }
                }) {
                    Image(systemName: "plus").font(.system(size: 18))
                }
                .frame(width: 44, height: 44)
                Button("应用参数") {
                    store.applyTags()
                    store.showToast("参数已应用到全部文件")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            if !store.mediaParams.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.mediaParams, id: \.self) { param in
                            Button(action: { store.mediaParams.removeAll { $0 == param } }) {
                                Label(param, systemImage: "xmark")
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.appContainer)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .onChange(of: store.tmdbKeyword) { _ in scheduleSearch() }
        .onChange(of: store.mediaType) { _ in
            if !store.tmdbKeyword.trimmingCharacters(in: .whitespaces).isEmpty {
                store.tmdbSelected = nil
                store.tmdbEpisodes = [:]
                store.tmdbResults = []
                Task { await doSearch() }
            }
        }
        .onChange(of: store.tmdbSeason) { newValue in
            guard store.mediaType == "tv", store.tmdbSelected != nil, !newValue.isEmpty else { return }
            seasonTask?.cancel()
            seasonTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await fetchSelectedEpisodes()
            }
        }
    }

    private func switchType(_ type: String) {
        store.mediaType = type
        store.dirMediaType[store.currentPath] = type
        store.tmdbSelected = nil
        store.tmdbEpisodes = [:]
        store.saveSetting()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let kw = store.tmdbKeyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            if store.tmdbKeyword.trimmingCharacters(in: .whitespaces) == kw {
                await doSearch()
            }
        }
    }

    func doSearch() async {
        guard !store.tmdbKeyword.trimmingCharacters(in: .whitespaces).isEmpty, !store.tmdbSearching else { return }
        store.tmdbSearching = true
        defer { store.tmdbSearching = false }
        let kw = store.tmdbKeyword.trimmingCharacters(in: .whitespaces)
        let cacheKey = "\(store.mediaType)_\(kw)"
        if let cached = store.tmdbSearchCache[cacheKey] {
            store.tmdbResults = cached
            if cached.isEmpty { store.showToast("没有搜到结果") }
            return
        }
        do {
            guard let ren = store.renamer else { return }
            let apiKey = store.tmdbApiKey.trimmingCharacters(in: .whitespaces)
            let raw: [TmdbResult]
            if store.mediaType == "movie" {
                // TVmaze has no movies: movies always go through TMDB.
                raw = try await ren.tmdbSearchMovie(keyword: kw, apiKey: apiKey)
            } else {
                switch store.scrapeSource {
                case "tvmaze":
                    raw = try await tvmazeSearch(keyword: kw)
                case "tmdb":
                    raw = try await ren.tmdbSearch(keyword: kw, apiKey: apiKey)
                default:
                    do { raw = try await ren.tmdbSearch(keyword: kw, apiKey: apiKey) }
                    catch { raw = try await tvmazeSearch(keyword: kw) }
                }
            }
            // TMDB ranks by popularity, so an unreleased sequel can outrank the
            // exact title (e.g. 复仇者联盟5 above 复仇者联盟 2012): exact matches first.
            let results = raw.sorted {
                ($0.name.trimmingCharacters(in: .whitespaces) == kw ? 0 : 1)
                    < ($1.name.trimmingCharacters(in: .whitespaces) == kw ? 0 : 1)
            }
            store.tmdbSearchCache[cacheKey] = results
            store.tmdbResults = results
            if results.isEmpty { store.showToast("没有搜到结果") }
        } catch {
            store.showToast("搜索失败：\(error.localizedDescription)")
        }
    }

    func fetchSelectedEpisodes() async {
        guard let res = store.tmdbSelected else { return }
        if store.mediaType == "movie" {
            store.fillFromSelection()
            store.saveScrape()
            store.showToast("已填入电影名")
            return
        }
        store.tmdbFetching = true
        store.fillFromSelection()
        defer { store.tmdbFetching = false }
        do {
            let season = Int(store.tmdbSeason) ?? 1
            let key = "\(store.scrapeSource)_\(res.id)_\(season)"
            if let cached = store.episodeCache[key] {
                store.tmdbEpisodes = cached
            } else {
                guard let ren = store.renamer else { return }
                let apiKey = store.tmdbApiKey.trimmingCharacters(in: .whitespaces)
                let eps: [String: String]
                switch store.scrapeSource {
                case "tvmaze":
                    eps = try await tvmazeEpisodes(id: res.id, season: season)
                case "tmdb":
                    eps = try await ren.tmdbFetch(id: res.id, season: season, apiKey: apiKey)
                default:
                    do { eps = try await ren.tmdbFetch(id: res.id, season: season, apiKey: apiKey) }
                    catch {
                        var fallback: [String: String] = [:]
                        if let alt = try? await tvmazeSearch(keyword: res.name).first {
                            fallback = (try? await tvmazeEpisodes(id: alt.id, season: season)) ?? [:]
                        }
                        eps = fallback
                    }
                }
                store.episodeCache[key] = eps
                store.tmdbEpisodes = eps
            }
            store.fillFromSelection()
            store.saveScrape()
            store.showToast("已填入剧名和集名")
        } catch {
            store.showToast("获取集名失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - Single-file edit sheet (with its own TMDB search)

struct EditSheet: View {
    @EnvironmentObject var store: AppState
    @ObservedObject var row: RowState
    var onRenameSingle: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var singleKeyword = ""
    @State private var singleResults: [TmdbResult] = []
    @State private var singleSearching = false
    @State private var singleTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Text(row.name)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if row.names.count > 1 {
                        Text("同名文件共 \(row.names.count) 个（\(row.names.map { ($0 as NSString).pathExtension }.joined(separator: "、") )，改名会一起改")
                            .font(.subheadline)
                            .foregroundColor(.appPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    TextField(store.mediaType == "movie" ? "电影名" : "剧名", text: $row.title)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: row.title) { _ in store.syncEpisodes() }

                    // Own search: fills only this row, never touches the panel selection.
                    HStack(spacing: 6) {
                        CompactField(text: $singleKeyword,
                                     placeholder: store.mediaType == "movie" ? "搜索电影名，只填这一行" : "搜索剧名，只填这一行",
                                     height: 44) { Task { await doSingleSearch() } }
                        Button(action: { Task { await doSingleSearch() } }) {
                            Group {
                                if singleSearching {
                                    ProgressView().frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "magnifyingglass").font(.system(size: 17))
                                }
                            }
                            .frame(width: 44, height: 44)
                            .background(Color.appPrimary)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(singleSearching)
                    }
                    if !singleResults.isEmpty {
                        PosterResultsView(results: singleResults, selectedId: nil) { res in
                            applySingleResult(res)
                        }
                    }

                    if store.mediaType == "movie" {
                        TextField("年份", text: $row.year)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .onChange(of: row.year) { _ in store.syncEpisodes() }
                    } else {
                        HStack(spacing: 8) {
                            TextField("季", text: $row.season)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .onChange(of: row.season) { _ in store.syncEpisodes() }
                            TextField("集", text: $row.episode)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .onChange(of: row.episode) { _ in store.syncEpisodes() }
                        }
                        TextField("集名（可选）", text: $row.epTitle)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: row.epTitle) { _ in store.syncEpisodes() }
                    }

                    TextField("媒体参数，逗号分隔", text: $row.tags)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: row.tags) { _ in store.syncEpisodes() }
                    let curTags = row.tags.split { ",，;；|".contains($0) }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if !curTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(curTags, id: \.self) { tag in
                                    Button(action: {
                                        row.tags = curTags.filter { $0 != tag }.joined(separator: ",")
                                        store.syncEpisodes()
                                    }) {
                                        Label(tag, systemImage: "xmark")
                                            .font(.subheadline)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.appContainer)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        Text("新名：").font(.subheadline).foregroundColor(.appPrimary)
                        DiffText(old: row.name, new: store.previewName(row))
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Button("重命名此文件", action: onRenameSingle)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .frame(maxWidth: .infinity)
                            .disabled(store.previewName(row) == row.name)
                        Button("完成") { dismiss() }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .navigationTitle("编辑文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onChange(of: singleKeyword) { _ in scheduleSingleSearch() }
    }

    private func scheduleSingleSearch() {
        singleTask?.cancel()
        let kw = singleKeyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        singleTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            if singleKeyword.trimmingCharacters(in: .whitespaces) == kw {
                await doSingleSearch()
            }
        }
    }

    private func doSingleSearch() async {
        guard !singleKeyword.trimmingCharacters(in: .whitespaces).isEmpty, !singleSearching else { return }
        singleSearching = true
        defer { singleSearching = false }
        let kw = singleKeyword.trimmingCharacters(in: .whitespaces)
        do {
            guard let ren = store.renamer else { return }
            let apiKey = store.tmdbApiKey.trimmingCharacters(in: .whitespaces)
            let raw: [TmdbResult]
            if store.mediaType == "movie" {
                raw = try await ren.tmdbSearchMovie(keyword: kw, apiKey: apiKey)
            } else {
                switch store.scrapeSource {
                case "tvmaze": raw = try await tvmazeSearch(keyword: kw)
                case "tmdb": raw = try await ren.tmdbSearch(keyword: kw, apiKey: apiKey)
                default:
                    do { raw = try await ren.tmdbSearch(keyword: kw, apiKey: apiKey) }
                    catch { raw = try await tvmazeSearch(keyword: kw) }
                }
            }
            singleResults = raw.sorted {
                ($0.name.trimmingCharacters(in: .whitespaces) == kw ? 0 : 1)
                    < ($1.name.trimmingCharacters(in: .whitespaces) == kw ? 0 : 1)
            }
            if singleResults.isEmpty { store.showToast("没有搜到结果") }
        } catch {
            store.showToast("搜索失败：\(error.localizedDescription)")
        }
    }

    private func applySingleResult(_ res: TmdbResult) {
        row.title = res.name
        if store.mediaType == "movie" {
            row.year = res.year
            store.syncEpisodes()
            store.showToast("已填入电影名")
        } else {
            store.syncEpisodes()
            Task {
                do {
                    guard let ren = store.renamer else { return }
                    let season = Int(row.season) ?? 1
                    let apiKey = store.tmdbApiKey.trimmingCharacters(in: .whitespaces)
                    let eps: [String: String]
                    switch store.scrapeSource {
                    case "tvmaze": eps = try await tvmazeEpisodes(id: res.id, season: season)
                    case "tmdb": eps = try await ren.tmdbFetch(id: res.id, season: season, apiKey: apiKey)
                    default:
                        do { eps = try await ren.tmdbFetch(id: res.id, season: season, apiKey: apiKey) }
                        catch {
                            var fallback: [String: String] = [:]
                            if let alt = try? await tvmazeSearch(keyword: res.name).first {
                                fallback = (try? await tvmazeEpisodes(id: alt.id, season: season)) ?? [:]
                            }
                            eps = fallback
                        }
                    }
                    if store.useEpisodeTitle, let t = eps[row.episode] {
                        row.epTitle = t.trimmingCharacters(in: .whitespaces)
                    }
                    store.syncEpisodes()
                    store.showToast("已填入剧名和集名")
                } catch {
                    store.showToast("获取集名失败：\(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Batch edit sheet

struct BatchSheet: View {
    @EnvironmentObject var store: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var bTitle = ""
    @State private var bSeason = ""
    @State private var bStart = ""
    @State private var bYear = ""
    @State private var bTags = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Text("批量编辑 \(store.selected.count) 个文件")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("留空的字段不改；填了起始集号会按列表顺序连续编号。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField(store.mediaType == "movie" ? "统一电影名" : "统一剧名", text: $bTitle)
                        .textFieldStyle(.roundedBorder)
                    if store.mediaType == "movie" {
                        TextField("统一年份", text: $bYear)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    } else {
                        HStack(spacing: 8) {
                            TextField("统一季号", text: $bSeason)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                            TextField("起始集号", text: $bStart)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }
                    }
                    TextField("统一媒体参数，逗号分隔", text: $bTags)
                        .textFieldStyle(.roundedBorder)
                    if store.mediaType == "tv" && !store.tmdbEpisodes.isEmpty {
                        Text("已刮削到 \(store.tmdbEpisodes.count) 集集名，应用时按集号自动填入。")
                            .font(.subheadline)
                            .foregroundColor(.appPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("应用到所选") {
                        let targets = store.rows.filter { store.selected.contains($0.name) }
                        var ep = Int(bStart)
                        for r in targets {
                            if !bTitle.trimmingCharacters(in: .whitespaces).isEmpty { r.title = bTitle.trimmingCharacters(in: .whitespaces) }
                            if store.mediaType == "movie" {
                                if !bYear.isEmpty { r.year = bYear }
                            } else {
                                if !bSeason.isEmpty { r.season = bSeason }
                                if let e = ep { r.episode = String(e); ep = e + 1 }
                                if store.useEpisodeTitle, let t = store.tmdbEpisodes[r.episode] {
                                    r.epTitle = t.trimmingCharacters(in: .whitespaces)
                                }
                            }
                            if !bTags.isEmpty { r.tags = bTags }
                        }
                        store.syncEpisodes()
                        store.batchOpen = false
                        store.showToast("已批量更新 \(targets.count) 个文件")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle("批量编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Confirm rename (progress + failed list)

struct ConfirmRenameView: View {
    @EnvironmentObject var store: AppState
    let changes: [RowState]
    var onClose: () -> Void

    @State private var running = false
    @State private var done = false
    @State private var total = 0
    @State private var doneCount = 0
    @State private var failedNames: [String] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                if running || done {
                    ProgressView(value: total > 0 ? Double(doneCount) / Double(total) : 0)
                    Text("正在改 \(doneCount)/\(total)").font(.subheadline)
                    if done {
                        let ok = doneCount - failedNames.count
                        Text("成功 \(ok) 个，失败 \(failedNames.count) 个")
                            .font(.subheadline)
                            .bold()
                        if !failedNames.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(failedNames, id: \.self) { name in
                                        Text(name)
                                            .font(.subheadline)
                                            .foregroundColor(.red)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxHeight: 160)
                        }
                        Button("完成") { onClose() }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(changes) { r in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(.subheadline).lineLimit(1)
                                    HStack(spacing: 2) {
                                        Text("→ ").font(.subheadline).foregroundColor(.secondary)
                                        DiffText(old: r.name, new: store.previewName(r))
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        if r.names.count > 1 {
                                            Text("（同名共 \(r.names.count) 个一起改）")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    HStack(spacing: 8) {
                        Button("取消") { onClose() }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .frame(maxWidth: .infinity)
                        Button("执行") { run() }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .frame(maxWidth: .infinity)
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle(done ? "重命名完成" : running ? "正在重命名" : "确认重命名 \(changes.count) 个文件？")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(running)
        }
    }

    private func run() {
        running = true
        done = false
        failedNames = []
        doneCount = 0
        var count = 0
        for r in changes {
            for fname in r.names {
                let ext = (fname as NSString).pathExtension
                let suffix = ext.isEmpty ? "" : ".\(ext)"
                if store.previewBase(r) + suffix != fname { count += 1 }
            }
        }
        total = count
        Task {
            if let ren = store.renamer {
                let alive = await ren.validateCurrentUser()
                if !alive { _ = await store.relogin() }
            }
            var okCount = 0
            let currentPath = store.currentPath
            func fullPath(_ name: String) -> String {
                currentPath == "/" ? "/\(name)" : "\(currentPath)/\(name)"
            }
            for r in changes {
                let base = store.previewBase(r)
                for fname in r.names {
                    let ext = (fname as NSString).pathExtension
                    let newName = base + (ext.isEmpty ? "" : ".\(ext)")
                    if newName == fname { continue }
                    do {
                        if let ren = store.renamer, try await ren.renameSingle(path: fullPath(fname), newName: newName) {
                            okCount += 1
                        } else {
                            failedNames.append(fname)
                        }
                    } catch {
                        failedNames.append(fname)
                    }
                    doneCount += 1
                }
            }
            running = false
            done = true
            if okCount > 0 {
                try? await store.loadDir(force: true)
            }
        }
    }
}
