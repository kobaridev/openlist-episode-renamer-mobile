import SwiftUI

// MARK: - Login screen (port of Android LoginScreen)

struct LoginView: View {
    @EnvironmentObject var store: AppState
    private let defaults = UserDefaults.standard

    @State private var url: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var error: String?
    @State private var busy = false

    private var canAutoLogin: Bool {
        !url.isEmpty && !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 16) {
                    // Login logo: same image as the Android login page.
                    Image("LoginLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 108, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color(.systemGray4), lineWidth: 1))
                        .padding(.top, 24)

                    VStack(spacing: 6) {
                        Text("OpenList 影视重命名")
                            .font(.title2)
                            .bold()
                            .multilineTextAlignment(.center)
                        Text("连接你的 OpenList 服务器")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        loginField(icon: "cloud", placeholder: "服务器地址", prompt: "例如 192.168.1.10:5244", text: $url, keyboard: .URL)
                        Text("连电脑上的 OpenList 请填局域网 IP，如 192.168.1.10:5244；127.0.0.1 指 iPad 自己")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        loginField(icon: "person", placeholder: "用户名", text: $username)
                        loginField(icon: "lock", placeholder: "密码", text: $password, isSecure: true)
                    }

                    if let error = error {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: attempt) {
                        Group {
                            if busy {
                                ProgressView().tint(.white)
                            } else {
                                Text("连接").bold()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.appPrimary)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)

                    Spacer(minLength: 24)

                    // shields.io-style badges (Android LoginScreen)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ShieldBadge(label: "GitHub", value: "KoBariDev") { openURL("https://github.com/KoBariDev") }
                            ShieldBadge(label: "Blog", value: "hub.131714.xyz") { openURL("https://hub.131714.xyz") }
                        }
                        ShieldBadge(label: "Repo", value: "openlist-episode-renamer") {
                            openURL("https://github.com/KoBariDev/openlist-episode-renamer")
                        }
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: min(geo.size.width, 560))
                .frame(minHeight: geo.size.height, alignment: .top)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if url.isEmpty {
                url = (defaults.string(forKey: "base_url") ?? "").isEmpty
                    ? "127.0.0.1:5244"
                    : (defaults.string(forKey: "base_url") ?? "")
            }
            if username.isEmpty { username = defaults.string(forKey: "username") ?? "" }
            if password.isEmpty { password = defaults.string(forKey: "password") ?? "" }
            if canAutoLogin { attempt() }
        }
    }


    // Text field with a leading icon (same icons as the Android login screen).
    private func loginField(icon: String, placeholder: String, prompt: String? = nil,
                           text: Binding<String>, keyboard: UIKeyboardType = .default,
                           isSecure: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text, prompt: prompt.map { Text($0) })
                } else {
                    TextField(placeholder, text: text, prompt: prompt.map { Text($0) })
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
    }

    private func attempt() {
        guard !busy else { return }
        if url.trimmingCharacters(in: .whitespaces).isEmpty { error = "服务器地址不能为空"; return }
        if username.trimmingCharacters(in: .whitespaces).isEmpty { error = "用户名不能为空"; return }
        if password.isEmpty { error = "密码不能为空"; return }
        busy = true
        error = nil
        Task {
            let message = await store.doLogin(base: url, user: username, pass: password)
            error = message
            busy = false
        }
    }

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            UIApplication.shared.open(url)
        }
    }
}
