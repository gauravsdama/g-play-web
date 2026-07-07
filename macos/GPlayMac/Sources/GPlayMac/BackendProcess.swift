import Darwin
import Foundation

struct BackendLaunch {
    let baseURL: URL
    let dataRootURL: URL
}

enum BackendError: LocalizedError {
    case missingResources(URL)
    case missingPython(URL)
    case noFreePort
    case healthCheckTimedOut

    var errorDescription: String? {
        switch self {
        case .missingResources(let url):
            return "Missing backend resources at \(url.path). Rebuild the app bundle."
        case .missingPython(let url):
            return "Missing bundled Python at \(url.path). Rebuild the app bundle."
        case .noFreePort:
            return "No free local port was available for the G Play backend."
        case .healthCheckTimedOut:
            return "The G Play backend did not become ready in time."
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
        let dataRootURL = try prepareDataRoot()
        let logsURL = dataRootURL.appendingPathComponent("logs", isDirectory: true)
        let logURL = logsURL.appendingPathComponent("gplay-backend-process.log")
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
            port: port
        )

        try process.run()

        self.process = process
        self.logHandle = handle

        return BackendLaunch(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            dataRootURL: dataRootURL
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

    private func prepareDataRoot() throws -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let dataRootURL = appSupport.appendingPathComponent("G Play", isDirectory: true)
        for child in ["library", "edited", "playlists", "logs"] {
            try FileManager.default.createDirectory(
                at: dataRootURL.appendingPathComponent(child, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return dataRootURL
    }

    private func backendEnvironment(resourcesURL: URL, dataRootURL: URL, port: Int) -> [String: String] {
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
        environment["GPLAY_LIBRARY_DIR"] = dataRootURL.appendingPathComponent("library").path
        environment["GPLAY_EDITED_DIR"] = dataRootURL.appendingPathComponent("edited").path
        environment["GPLAY_PLAYLISTS_DIR"] = dataRootURL.appendingPathComponent("playlists").path
        environment["GPLAY_LOGS_DIR"] = dataRootURL.appendingPathComponent("logs").path

        let cookiesURL = dataRootURL.appendingPathComponent("cookies.txt")
        if FileManager.default.fileExists(atPath: cookiesURL.path) {
            environment["GPLAY_YTDLP_COOKIES"] = cookiesURL.path
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
