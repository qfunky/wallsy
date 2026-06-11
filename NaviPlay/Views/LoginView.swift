import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppState

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var remember = true

    var body: some View {
        ZStack {
            Color.spBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.spGreen)
                            .frame(width: 64, height: 64)
                        Image(systemName: "music.note")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                    }
                    Text("Wallsy")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    Text("Connect to your Navidrome server")
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                }

                if !app.recentLogins.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECENT")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.3)
                            .foregroundColor(.spSubtext)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(app.recentLogins) { recent in
                                    Button {
                                        server = recent.server
                                        username = recent.username
                                        password = ""
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "server.rack")
                                                .font(.system(size: 10))
                                            Text(recentLabel(recent))
                                                .font(.system(size: 11, weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.white.opacity(0.1)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(width: 340)
                }

                VStack(alignment: .leading, spacing: 14) {
                    field("Server URL", text: $server, prompt: "https://music.example.com")
                    field("Username", text: $username, prompt: "admin")

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Password")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.spSubtext)
                        SecureField("", text: $password, prompt: Text("••••••••"))
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .onSubmit(submit)
                    }

                    Toggle("Remember me", isOn: $remember)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .foregroundColor(.spSubtext)
                }
                .frame(width: 340)

                if let error = app.loginError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .frame(width: 340)
                        .multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    ZStack {
                        Capsule()
                            .fill(canSubmit ? Color.spGreen : Color.spGreen.opacity(0.4))
                            .frame(width: 340, height: 46)
                        if app.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Connect")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || app.isBusy)
            }
            .padding(40)
        }
    }

    private func recentLabel(_ recent: AppState.RecentLogin) -> String {
        var host = recent.server
        host = host.replacingOccurrences(of: "http://", with: "")
        host = host.replacingOccurrences(of: "https://", with: "")
        return "\(recent.username) @ \(host)"
    }

    private var canSubmit: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.isEmpty
            && !password.isEmpty
    }

    private func submit() {
        guard canSubmit, !app.isBusy else { return }
        Task {
            await app.login(server: server, username: username, password: password, remember: remember)
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.spSubtext)
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                )
                .autocorrectionDisabled()
                .onSubmit(submit)
        }
    }
}
