import SwiftUI
import SwiftData

struct ConnectionSettingsTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @AppStorage("gitlab_url") private var gitlabURL: String = "https://gitlab.com"
    @State private var token: String = ""
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var connectedUserName: String?
    @State private var isTesting: Bool = false

    private let gitLabService = GitLabService()

    enum ConnectionStatus {
        case unknown, testing, connected, failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // GitLab Instance
            VStack(alignment: .leading, spacing: 6) {
                Text("GitLab Instance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("GitLab URL", text: $gitlabURL)
                    .textFieldStyle(.roundedBorder)

                Text("Base URL of your GitLab instance. Use **https://gitlab.com** for GitLab.com (not your group URL).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Authentication
            VStack(alignment: .leading, spacing: 6) {
                Text("Authentication")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("Personal Access Token", text: $token)
                    .textFieldStyle(.roundedBorder)

                Text("Create a legacy token at GitLab \u{2192} Profile \u{2192} Access Tokens with the **read_api** scope.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Actions
            VStack(spacing: 10) {
                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(token.isEmpty || isTesting)

                    Spacer()

                    switch connectionStatus {
                    case .unknown:
                        EmptyView()
                    case .testing:
                        ProgressView()
                            .controlSize(.small)
                        Text("Testing...")
                            .foregroundStyle(.secondary)
                    case .connected:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let name = connectedUserName {
                            Text("Connected as \(name)")
                        }
                    case .failed(let error):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                HStack {
                    Button("Save & Start Polling") {
                        saveAndStart()
                    }
                    .disabled(token.isEmpty)
                    .keyboardShortcut(.defaultAction)

                    if appState.isConnected {
                        Button("Stop Polling") {
                            appState.stopPolling()
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding()
        .onAppear {
            if let saved = KeychainStore.loadToken() {
                token = saved
            }
        }
    }

    private func testConnection() {
        connectionStatus = .testing
        isTesting = true
        Task {
            do {
                if let url = URL(string: gitlabURL) {
                    await gitLabService.updateBaseURL(url)
                }
                let name = try await gitLabService.testConnection(token: token)
                connectedUserName = name
                connectionStatus = .connected
                isTesting = false
            } catch {
                connectionStatus = .failed(error.localizedDescription)
                isTesting = false
            }
        }
    }

    private func saveAndStart() {
        do {
            try KeychainStore.saveToken(token)
            appState.restartPolling(modelContainer: modelContext.container)
            connectionStatus = .connected
        } catch {
            connectionStatus = .failed("Failed to save token: \(error.localizedDescription)")
        }
    }
}
