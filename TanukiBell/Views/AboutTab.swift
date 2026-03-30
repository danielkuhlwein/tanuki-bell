import SwiftUI

struct AboutTab: View {
    @EnvironmentObject private var updaterController: UpdaterController

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon + name
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            VStack(spacing: 4) {
                Text("Tanuki Bell")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Check for Updates...") {
                updaterController.checkForUpdates()
            }

            VStack(spacing: 4) {
                Link("GitHub Repository",
                     destination: URL(string: "https://github.com/danielkuhlwein/tanuki-bell")!)
                    .font(.caption)

                Text("MIT Licence")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
