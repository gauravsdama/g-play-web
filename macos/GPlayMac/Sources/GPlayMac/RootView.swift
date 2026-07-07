import AppKit
import SwiftUI
import WebKit

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var webViewModel = WebViewModel()

    var body: some View {
        ZStack {
            switch model.state {
            case .starting:
                StartupView(message: "Starting G Play")
            case .ready(let url):
                GPlayWebView(model: webViewModel)
                    .onAppear {
                        webViewModel.load(url)
                    }
            case .failed(let message):
                FailureView(message: message)
            }
        }
        .frame(minWidth: 1120, minHeight: 760)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.shutdown()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    webViewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back")

                Button {
                    webViewModel.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Forward")

                Button {
                    webViewModel.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
            }

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
    }
}

struct FailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.orange)
            Text("G Play could not start")
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

@MainActor
final class WebViewModel: ObservableObject {
    let webView: WKWebView
    private var loadedURL: URL?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true
        self.webView.allowsMagnification = false
        self.webView.setValue(false, forKey: "drawsBackground")
    }

    func load(_ url: URL) {
        guard loadedURL != url else {
            return
        }
        loadedURL = url
        webView.load(URLRequest(url: url))
    }

    func reload() {
        webView.reload()
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
}

struct GPlayWebView: NSViewRepresentable {
    @ObservedObject var model: WebViewModel

    func makeNSView(context: Context) -> WKWebView {
        model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
