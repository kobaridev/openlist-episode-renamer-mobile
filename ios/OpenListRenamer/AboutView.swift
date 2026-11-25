import SwiftUI

// MARK: - About page (text version, no GitHub stats card)

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    /// Version follows the release automatically — never hardcoded.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private let features = [
        "剧集 / 电影分类：按 SxxEyy 自动识别类型，也可手动切换",
        "TMDB / TVmaze 刮削：剧名、集名、电影名与年份自动填入",
        "批量编号：按列表顺序为剧集连续编号",
        "媒体参数识别：分辨率、编码、HDR、音频、字幕语言自动识别",
        "单文件重命名与单文件搜索：只改一个文件，不动其他的",
        "目录缓存与按目录记忆：刮削结果和类型每个目录单独记住",
        "深色模式",
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OpenList 影视重命名" + (appVersion.isEmpty ? "" : " · v\(appVersion)"))
                            .font(.title3)
                            .bold()
                        Text("连接 OpenList 服务器，按 TMDB 标准批量规范影视文件名。剧集命名为「剧名.SxxEyy.集名.参数」，电影命名为「片名 (年份).参数」；支持 TMDB 与 TVmaze 刮削、批量编号、媒体参数自动识别、单文件重命名。")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("功能")
                            .font(.headline)
                        ForEach(features, id: \.self) { feature in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundColor(.appPrimary)
                                Text(feature).font(.body)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("作者")
                            .font(.headline)
                        Text("KoBariDev，openlist-episode-renamer 的作者，个人博客 hub.131714.xyz。")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        linkRow(label: "GitHub", urlText: "github.com/KoBariDev", url: "https://github.com/KoBariDev")
                        linkRow(label: "博客", urlText: "hub.131714.xyz", url: "https://hub.131714.xyz")
                        linkRow(label: "项目仓库", urlText: "github.com/KoBariDev/openlist-episode-renamer", url: "https://github.com/KoBariDev/openlist-episode-renamer")
                    }
                }
                .padding(20)
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func linkRow(label: String, urlText: String, url: String) -> some View {
        Button(action: {
            if let link = URL(string: url) {
                UIApplication.shared.open(link)
            }
        }) {
            HStack(spacing: 4) {
                Text(label + "：")
                    .font(.body)
                    .foregroundColor(.primary)
                Text(urlText)
                    .font(.body)
                    .foregroundColor(.appPrimary)
            }
        }
        .buttonStyle(.plain)
    }
}
