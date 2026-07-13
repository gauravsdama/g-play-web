import Darwin
import Foundation

struct BackendLaunch {
    let baseURL: URL
    let dataRootURL: URL
    let apiToken: String
}

enum BackendError: LocalizedError {
    case missingResources(URL)
    case missingPython(URL)
    case noFreePort
    case healthCheckTimedOut

    var errorDescription: String? {
        switch self {
        case .missingResources(let url):
            return "Missing media engine resources at \(url.path). Rebuild the app bundle."
        case .missingPython(let url):
            return "Missing bundled Python at \(url.path). Rebuild the app bundle."
        case .noFreePort:
            return "No free local port was available for the vantabeat media engine."
        case .healthCheckTimedOut:
            return "The vantabeat media engine did not become ready in time."
        }
    }
}

@MainActor
final class BackendProcess {
    private var process: Process?
    private var logHandle: FileHandle?

    func start() throws -> BackendLaunch {
        stop()

        let resourcesURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let backendURL = resourcesURL.appendingPathComponent("backend", isDirectory: true)
        let pythonURL = resourcesURL
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")

        guard FileManager.default.fileExists(atPath: backendURL.appendingPathComponent("app/main.py").path) else {
            throw BackendError.missingResources(backendURL)
        }
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw BackendError.missingPython(pythonURL)
        }

        let port = try findPort(startingAt: 9137)
        let dataRootURL = try prepareDataRoot(resourcesURL: resourcesURL)
        let apiToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let logsURL = dataRootURL.appendingPathComponent("logs", isDirectory: true)
        let logURL = logsURL.appendingPathComponent("vantabeat-engine-process.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "-m", "uvicorn",
            "backend.app.main:app",
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--no-access-log",
        ]
        process.currentDirectoryURL = resourcesURL
        process.standardOutput = handle
        process.standardError = handle
        process.environment = backendEnvironment(
            resourcesURL: resourcesURL,
            dataRootURL: dataRootURL,
            port: port,
            apiToken: apiToken
        )

        try process.run()

        self.process = process
        self.logHandle = handle

        return BackendLaunch(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            dataRootURL: dataRootURL,
            apiToken: apiToken
        )
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        try? logHandle?.close()
        logHandle = nil
    }

    deinit {
        process?.terminate()
        try? logHandle?.close()
    }

    private func prepareDataRoot(resourcesURL: URL) throws -> URL {
        if let projectRootURL = developmentProjectRoot(resourcesURL: resourcesURL) {
            for child in ["library", "edited", "playlists", "logs"] {
                try FileManager.default.createDirectory(
                    at: projectRootURL.appendingPathComponent(child, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            return projectRootURL
        }

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let dataRootURL = appSupport.appendingPathComponent("vantabeat", isDirectory: true)
        for child in ["library", "edited", "playlists", "logs"] {
            try FileManager.default.createDirectory(
                at: dataRootURL.appendingPathComponent(child, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return dataRootURL
    }

    private func developmentProjectRoot(resourcesURL: URL) -> URL? {
        let markerURL = resourcesURL.appendingPathComponent("vantabeat-project-root.txt")
        guard
            let contents = try? String(contentsOf: markerURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !contents.isEmpty
        else {
            return nil
        }

        let projectRootURL = URL(fileURLWithPath: contents, isDirectory: true)
        let backendURL = projectRootURL.appendingPathComponent("backend/app/main.py")
        guard FileManager.default.fileExists(atPath: backendURL.path) else {
            return nil
        }
        return projectRootURL
    }

    private func backendEnvironment(resourcesURL: URL, dataRootURL: URL, port: Int, apiToken: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            environment["PATH"] ?? "",
        ].joined(separator: ":")
        environment["PORT"] = "\(port)"
        environment["PYTHONPATH"] = resourcesURL.path
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["VANTABEAT_API_TOKEN"] = apiToken
        environment["VANTABEAT_LIBRARY_DIR"] = dataRootURL.appendingPathComponent("library").path
        environment["VANTABEAT_EDITED_DIR"] = dataRootURL.appendingPathComponent("edited").path
        environment["VANTABEAT_PLAYLISTS_DIR"] = dataRootURL.appendingPathComponent("playlists").path
        environment["VANTABEAT_LOGS_DIR"] = dataRootURL.appendingPathComponent("logs").path

        let cookiesURL = dataRootURL.appendingPathComponent("cookies.txt")
        if FileManager.default.fileExists(atPath: cookiesURL.path) {
            environment["VANTABEAT_YTDLP_COOKIES"] = cookiesURL.path
        }

        return environment
    }

    private func findPort(startingAt start: Int) throws -> Int {
        for port in start..<(start + 80) {
            if canBind(port: port) {
                return port
            }
        }
        throw BackendError.noFreePort
    }

    private func canBind(port: Int) -> Bool {
        let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            return false
        }
        defer {
            close(fileDescriptor)
        }

        var value: Int32 = 1
        setsockopt(fileDescriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
