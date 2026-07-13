import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            switch model.state {
            case .starting:
                StartupView(message: "Starting vantabeat")
            case .ready(let url, let apiToken):
                NativeAppView(baseURL: url, apiToken: apiToken, dataRootURL: model.dataRootURL)
            case .failed(let message):
                FailureView(message: message)
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.shutdown()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.openDataFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open Data Folder")

                Button {
                    Task {
                        await model.restart()
                    }
                } label: {
                    Image(systemName: "bolt.horizontal.circle")
                }
                .help("Restart Backend")
            }
        }
    }
}

struct StartupView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.headline)
            Text("Preparing the local audio engine")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

struct FailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("vantabeat could not start")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 520)
        }
        .padding(40)
    }
}
