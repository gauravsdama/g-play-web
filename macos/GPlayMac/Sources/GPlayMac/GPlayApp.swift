import AppKit
import SwiftUI

@main
struct GPlayApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("G Play") {
            RootView()
                .environmentObject(model)
                .task {
                    await model.start()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open G Play Data Folder") {
                    model.openDataFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Restart Backend") {
                    Task {
                        await model.restart()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum State: Equatable {
        case starting
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .starting
    @Published private(set) var dataRootURL: URL?

    private let backend = BackendProcess()
    private var hasStarted = false

    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        await launchBackend()
    }

    func restart() async {
        shutdown()
        state = .starting
        await launchBackend()
    }

    func shutdown() {
        backend.stop()
        hasStarted = false
    }

    func openDataFolder() {
        guard let dataRootURL else {
            return
        }
        NSWorkspace.shared.open(dataRootURL)
    }

    private func launchBackend() async {
        do {
            let launch = try backend.start()
            dataRootURL = launch.dataRootURL
            try await waitForBackend(at: launch.baseURL)
            state = .ready(launch.baseURL)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func waitForBackend(at baseURL: URL) async throws {
        let healthURL = baseURL.appendingPathComponent("api/health")
        var lastError: Error?

        for _ in 0..<100 {
            do {
                let (_, response) = try await URLSession.shared.data(from: healthURL)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    return
                }
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        throw lastError ?? BackendError.healthCheckTimedOut
    }
}
