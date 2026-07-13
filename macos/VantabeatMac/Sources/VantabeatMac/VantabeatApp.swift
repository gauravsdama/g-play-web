import AppKit
import SwiftUI

@main
struct VantabeatApp: App {
    @NSApplicationDelegateAdaptor(VantabeatAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open vantabeat Data Folder") {
                    VantabeatRuntime.shared.model.openDataFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Restart Backend") {
                    Task {
                        await VantabeatRuntime.shared.model.restart()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class VantabeatRuntime {
    static let shared = VantabeatRuntime()

    let model = AppModel()

    private init() {}
}

@MainActor
final class VantabeatAppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = VantabeatRuntime.shared
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
        Task {
            await runtime.model.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.model.shutdown()
    }

    private func showMainWindow() {
        let window = mainWindow ?? makeMainWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMainWindow() -> NSWindow {
        let controller = NSHostingController(
            rootView: RootView()
                .environmentObject(runtime.model)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "vantabeat"
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("vantabeat-main-window")
        window.center()
        mainWindow = window
        return window
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum State: Equatable {
        case starting
        case ready(URL, String)
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
            state = .ready(launch.baseURL, launch.apiToken)
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
