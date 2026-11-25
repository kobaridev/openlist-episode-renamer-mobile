import SwiftUI

// MARK: - Colors (same white-blue scheme as the Android build)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    static let appPrimary = Color(hex: 0x0B57D0)
    static let appPrimaryLight = Color(hex: 0x8AB8FF)
    static let appContainer = Color(hex: 0xD3E3FD)
    static let appContainerDark = Color(hex: 0x1E4470)

    /// Light-blue -> white gradient used behind both themes (mirrors Android).
    static func pageGradient(dark: Bool) -> LinearGradient {
        if dark {
            return LinearGradient(colors: [Color(hex: 0x16305A), Color(hex: 0x0C1A30), Color(hex: 0x0A1526)],
                                  startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [Color(hex: 0xD9E9FF), Color(hex: 0xF2F7FF), Color.white],
                              startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Poster image with in-memory cache

final class PosterCache {
    static let shared = NSCache<NSString, UIImage>()
}

struct PosterImage: View {
    let urlString: String
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "film")
                        .foregroundColor(.secondary)
                }
            }
        }
        .task(id: urlString) {
            if urlString.isEmpty { return }
            if let cached = PosterCache.shared.object(forKey: urlString as NSString) {
                image = cached
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: URL(string: urlString)!)
                if let ui = UIImage(data: data) {
                    PosterCache.shared.setObject(ui, forKey: urlString as NSString)
                    image = ui
                }
            } catch {
                // Leave the placeholder in place.
            }
        }
    }
}

// MARK: - Compact input (hand-drawn border, never clips text like a fixed-height TextField)

struct CompactField: View {
    var text: Binding<String>
    var placeholder: String = ""
    var numeric: Bool = false
    var height: CGFloat = 46
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: text)
            .focused($focused)
            .keyboardType(numeric ? .numberPad : .default)
            .submitLabel(onSubmit == nil ? .return : .search)
            .onSubmit { onSubmit?() }
            .frame(height: height)
            .padding(.horizontal, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focused ? Color.appPrimary : Color(.systemGray4), lineWidth: focused ? 1.5 : 1)
            )
    }
}

struct LabeledField: View {
    var text: Binding<String>
    var label: String
    var numeric: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundColor(.secondary)
            CompactField(text: text, numeric: numeric)
        }
    }
}

// MARK: - Diff-highlighted new name (changed middle in primary + bold)

struct DiffText: View {
    let old: String
    let new: String

    var body: some View {
        let (pre, mid, suf) = diffParts(old: old, new: new)
        Text(pre)
            .foregroundColor(.secondary)
        + Text(mid)
            .foregroundColor(.appPrimary)
            .bold()
        + Text(suf)
            .foregroundColor(.secondary)
    }
}

// MARK: - Login logo (drawn, mirrors the Android icon artwork)

struct LoginLogo: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2E7CF6), Color(hex: 0x0B57D0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .frame(width: 56, height: 40)
                    Image(systemName: "play.fill")
                        .foregroundColor(.appPrimary)
                        .font(.system(size: 16))
                }
                Text("S01E01")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - shields.io-style two-tone badge (login screen)

struct ShieldBadge: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(hex: 0x2F3B4C))
                Text(value)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.appPrimary)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small stat box (GitHub card)

struct StatBox: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).bold()
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray6).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Pill toggle chip (剧集 / 电影）

struct TypeChip: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.appPrimary : Color(.systemGray5))
                .foregroundColor(selected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
