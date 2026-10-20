import AppKit
import ApplicationServices
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
    private var synergyItem: NSMenuItem!
    private var accessibilityTrusted = false
    private var lastSwitch: TimeInterval?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        buildMenu()
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityTrusted = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        video.onClick = { [weak self] in self?.switchSynergy() }
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

    // MARK: Synergy switch

    /// Thin posting layer; the decision lives in SynergySwitch.shouldSend.
    private func switchSynergy() {
        let now = ProcessInfo.processInfo.systemUptime
        guard SynergySwitch.shouldSend(enabled: SynergySwitch.isEnabled(), trusted: accessibilityTrusted,
                                       lastSent: lastSwitch, now: now) else { return }
        lastSwitch = now
        guard let pointer = CGEvent(source: nil)?.location else { return }
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success, count > 0 else { return }
        let desktop = ids.prefix(Int(count)).map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
        for point in SynergySwitch.edgePath(from: pointer, desktop: desktop) {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    private func refreshStatus() {
        if SynergySwitch.isEnabled() && !accessibilityTrusted {
            video.status = SynergySwitch.untrustedStatus
            return
        }
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
        window.initialFirstResponder = video
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
        view.addItem(.separator())
        synergyItem = view.addItem(withTitle: "Switch Synergy on Click", action: #selector(toggleSynergy), keyEquivalent: "")
        synergyItem.target = self
        synergyItem.state = SynergySwitch.isEnabled() ? .on : .off
        viewItem.submenu = view
        NSApp.mainMenu = main
    }

    @objc private func actualSize() { window.setContentSize(ViewGeometry.size(scale: 1)) }
    @objc private func doubleSize() { window.setContentSize(ViewGeometry.size(scale: 2)) }

    @objc private func toggleSynergy() {
        let on = !SynergySwitch.isEnabled()
        SynergySwitch.setEnabled(on)
        synergyItem.state = on ? .on : .off
    }

    @objc private func toggleOnTop() {
        let on = window.level != .floating
        window.level = on ? .floating : .normal
        alwaysOnTopItem.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "alwaysOnTop")
    }
}
