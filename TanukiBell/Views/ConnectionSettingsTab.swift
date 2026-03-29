import SwiftUI

struct ConnectionSettingsTab: View {
    @State private var gitlabURL: String = "https://gitlab.com"
    @State private var token: String = ""
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var connectedUserName: String?
    @State private var isTesting: Bool = false

    private let gitLabService = GitLabService()

    enum ConnectionStatus {
        case unknown, testing, connected, failed(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("GitLab URL", text: $gitlabURL)
                    .textFieldStyle(.roundedBorder)

                SecureField("Personal Access Token", text: $token)
                    .textFieldStyle(.roundedBorder)

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

                Button("Save Token") {
                    saveToken()
                }
                .disabled(token.isEmpty)
            }
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
                await MainActor.run {
                    connectedUserName = name
                    connectionStatus = .connected
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func saveToken() {
        do {
            try KeychainStore.saveToken(token)
        } catch {
            print("Failed to save token: \(error)")
        }
    }
}
