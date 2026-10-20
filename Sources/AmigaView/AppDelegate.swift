import AppKit
import AmigaViewCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let video = VideoView(frame: NSRect(origin: .zero, size: ViewGeometry.actualSize))
    private let tunnel = TunnelManager()
    private let settings = Settings.load()
    private var client: StreamClient?
    private var fpsMeter = FPSMeter()
    private var lastFrame: Date?
    private var baseStatus = "Connecting"
    private var statusTimer: Timer?
    private var alwaysOnTopItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        refreshStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshStatus() }
        startStreaming()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        client?.stop()
        tunnel.stop()
    }

    // MARK: Streaming

    private func startStreaming() {
        let s = settings
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let failure = self.tunnel.ensure(settings: s)
            DispatchQueue.main.async {
                if let failure { self.baseStatus = "Tunnel failed: \(failure)"; self.refreshStatus() }
                // Still try: the stream may be reachable some other way.
                let c = StreamClient(settings: s)
                c.onFrame = { [weak self] image in
                    guard let self else { return }
                    self.video.image = image
                    self.lastFrame = Date()
                    self.fpsMeter.tick(at: Date.timeIntervalSinceReferenceDate)
                }
                c.onEvent = { [weak self] text in
                    guard let self, self.lastFrame == nil, !self.baseStatus.hasPrefix("Tunnel failed") else { return }
                    self.baseStatus = text
                }
                self.client = c
                c.start()
            }
        }
    }

    private func refreshStatus() {
        let now = Date.timeIntervalSinceReferenceDate
        let fps = fpsMeter.fps(at: now)
        if let last = lastFrame, Date().timeIntervalSince(last) < 3 {
            let mode = client?.usingSnapshotFallback == true ? " (snapshot polling)" : ""
            video.status = String(format: "%.0f FPS%@", fps, mode)
        } else if lastFrame != nil {
            video.status = "No signal"
        } else if baseStatus == "Connecting" || baseStatus == "Stream dropped" {
            video.status = baseStatus
        } else {
            video.status = baseStatus
        }
    }

    // MARK: Window and menu

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: ViewGeometry.actualSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Amiga-View"
        window.contentView = video
        window.contentAspectRatio = ViewGeometry.actualSize
        window.contentMinSize = ViewGeometry.size(scale: 0.5)
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("MainWindow") { window.center() }
        window.setFrameAutosaveName("MainWindow")
        window.level = UserDefaults.standard.bool(forKey: "alwaysOnTop") ? .floating : .normal
        window.makeKeyAndOrderFront(nil)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Amiga-View", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Actual Size", action: #selector(actualSize), keyEquivalent: "1").target = self
        view.addItem(withTitle: "Double Size", action: #selector(doubleSize), keyEquivalent: "2").target = self
        view.addItem(.separator())
        alwaysOnTopItem = view.addItem(withTitle: "Always on Top", action: #selector(toggleOnTop), keyEquivalent: "t")
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = window.level == .floating ? .on : .off
        viewItem.submenu = view
        NSApp.mainMenu = main
    }

    @objc private func actualSize() { window.setContentSize(ViewGeometry.size(scale: 1)) }
    @objc private func doubleSize() { window.setContentSize(ViewGeometry.size(scale: 2)) }

    @objc private func toggleOnTop() {
        let on = window.level != .floating
        window.level = on ? .floating : .normal
        alwaysOnTopItem.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "alwaysOnTop")
    }
}
