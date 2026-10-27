import AppKit
import ApplicationServices
import AmigaViewCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var window: NSWindow!
    let video = VideoView(frame: NSRect(origin: .zero, size: ViewGeometry.actualSize))
    private let tunnel = TunnelManager()
    let edgeGuard = EdgeGuard()
    /// Where the window frame is saved; tests set nil so they leave the user's window alone.
    var frameAutosaveName: String? = "MainWindow"
    var defaults = UserDefaults.standard
    private let settings = Settings.load()
    private var client: StreamClient?
    private var audio: AudioStreamClient?
    private var player: AudioPlayer?
    private var fpsMeter = FPSMeter()
    private var lastFrame: Date?
    private var baseStatus = "Connecting"
    private var statusTimer: Timer?
    /// Where snapshots and recordings go; tests point them at a temp directory.
    var snapshotDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    var recordingDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
    static let flashDuration: TimeInterval = 3
    private var flash: (text: String, until: TimeInterval)?
    private(set) var recorder: Recorder?
    private var recordingStartedAt: TimeInterval = 0
    private var recordItem: NSMenuItem!
    /// Runs on the main queue when a stopped recording is finished and playable; replaced by tests.
    var recordingFinished: ((URL) -> Void)?
    private var alwaysOnTopItem: NSMenuItem!
    private var synergyItem: NSMenuItem!
    private var soundItem: NSMenuItem!
    private var pictureItems: [PictureOption: NSMenuItem] = [:]
    /// Posts the edge crossing; replaced by tests.
    lazy var performSwitch: () -> Void = { [weak self] in self?.postEdgeCrossing() }
    /// Full screen state and exit. Injected so tests need no real full-screen transition.
    lazy var isFullScreen: () -> Bool = { [weak self] in self?.window.styleMask.contains(.fullScreen) ?? false }
    lazy var exitFullScreen: () -> Void = { [weak self] in self?.window.toggleFullScreen(nil) }
    /// Asks before a reset; replaced by tests.
    lazy var confirmReset: () -> Bool = {
        let alert = NSAlert()
        alert.messageText = AmigaReset.confirmText
        alert.informativeText = AmigaReset.confirmDetail
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    /// Environment for the wasabi client; nil inherits the app's. Tests point it at a temp config.
    var resetEnvironment: [String: String]?
    /// Runs on the main queue with the status text when a reset finishes; replaced by tests.
    var resetFinished: ((String) -> Void)?
    /// Where a wasabid key typed in Settings is kept; tests use their own item.
    var keychain = Keychain.wasabi
    private(set) var settingsWindow: SettingsWindowController?
    static let settingsSavedStatus = "Settings saved"
    static let fullScreenHint = "Press Esc or Control-Command-F to leave full screen"
    var accessibilityTrusted = false
    private var lastSwitch: TimeInterval?
    /// Replaced by tests with a monitor on a temp log.
    lazy var deskflow = DeskflowMonitor(path: DeskflowLog.path(), clock: { ProcessInfo.processInfo.systemUptime },
                                                trusted: { [weak self] in self?.accessibilityTrusted ?? false })
    /// `--stats`: print frames decoded and drawn every 5 s to stderr, to measure the rate the app shows.
    private let printStats = CommandLine.arguments.contains("--stats")
    private var statsDrawn = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        buildMenu()
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityTrusted = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        video.onClick = { [weak self] in self?.switchSynergy(clickAt: $0) }
        NSApp.activate(ignoringOtherApps: true)
        refreshStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshStatus() }
        startStreaming()
        if printStats {
            var last = (drawn: 0, at: Date())
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                guard let self else { return }
                let now = Date(), secs = now.timeIntervalSince(last.at)
                let b = self.audio?.buffer
                FileHandle.standardError.write(String(format: "stats drawn=%.1f/s total=%d audio_bytes=%d buffered_ms=%.0f underruns=%d dropped=%d\n",
                    Double(self.statsDrawn - last.drawn) / secs, self.statsDrawn, self.audio?.bytesReceived ?? 0,
                    Double(b?.bufferedFrames ?? 0) / AudioStreamClient.sampleRate * 1000,
                    b?.underruns ?? 0, b?.droppedFrames ?? 0).data(using: .utf8)!)
                last = (self.statsDrawn, now)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        recorder?.finishAndWait()
        client?.stop()
        audio?.stop()
        player?.stop()
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
                c.onFrame = { [weak self] image in self?.handleFrame(image) }
                c.onEvent = { [weak self] text in
                    guard let self, self.lastFrame == nil, !self.baseStatus.hasPrefix("Tunnel failed") else { return }
                    self.baseStatus = text
                }
                self.client = c
                c.start()
                if AudioStreamClient.isEnabled() { self.startAudio() }
            }
        }
    }

    func handleFrame(_ image: CGImage) {
        video.image = image
        statsDrawn += 1
        lastFrame = Date()
        fpsMeter.tick(at: Date.timeIntervalSinceReferenceDate)
        recorder?.push(frame: image, at: ProcessInfo.processInfo.systemUptime)
    }

    private func startAudio() {
        guard audio == nil else { return }
        let a = AudioStreamClient(settings: settings)
        let p = AudioPlayer(buffer: a.buffer)
        do { try p.start() } catch { NSLog("Amiga-View: audio output failed: \(error)") }
        audio = a; player = p
        if let recorder { a.onPCM = { recorder.push(pcm: $0) } }
        a.start()
    }

    private func stopAudio() {
        audio?.stop()
        player?.stop()
        audio = nil; player = nil
    }

    // MARK: Snapshot and recording

    /// The crop the picture is shown with.
    private var currentCrop: CGRect {
        PictureOption.cropOverscan.isEnabled(in: defaults) ? ViewGeometry.cropRect(in: defaults) : ViewGeometry.fullField
    }

    /// Full screen hides the title bar and its buttons, so say how to get out.
    @objc private func didEnterFullScreen() { showFlash(Self.fullScreenHint) }

    private func showFlash(_ text: String) {
        flash = (text, ProcessInfo.processInfo.systemUptime + Self.flashDuration)
        refreshStatus()
    }

    @objc private func saveSnapshot() {
        guard let field = video.image else { showFlash("No picture to save"); return }
        guard let image = ViewGeometry.displayImage(from: field, crop: currentCrop), let png = CaptureFile.png(image) else {
            showFlash("Snapshot failed"); return
        }
        let url = CaptureFile.url(in: snapshotDirectory, date: Date(), ext: "png")
        do { try png.write(to: url); showFlash("Saved \(url.lastPathComponent)") }
        catch { showFlash("Snapshot failed: \(error.localizedDescription)") }
    }

    @objc private func resetAmiga() {
        guard confirmReset() else { return }
        showFlash(AmigaReset.startedStatus)
        AmigaReset.load(from: defaults, keychain: keychain).run(script: AmigaReset.scriptURL(), environment: resetEnvironment) { [weak self] text in
            self?.showFlash(text)
            self?.resetFinished?(text)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController(defaults: defaults, keychain: keychain)
            controller.saved = { [weak self] in self?.showFlash(Self.settingsSavedStatus) }
            settingsWindow = controller
        } else {
            settingsWindow?.load()
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleRecording() {
        if let r = recorder { stopRecording(r) } else { startRecording() }
    }

    private func startRecording() {
        let url = CaptureFile.url(in: recordingDirectory, date: Date(), ext: "mov")
        do {
            let r = try Recorder(url: url, crop: currentCrop, withAudio: audio != nil)
            recorder = r
            recordingStartedAt = ProcessInfo.processInfo.systemUptime
            audio?.onPCM = { r.push(pcm: $0) }
            recordItem.title = "Stop Recording"
        } catch { showFlash("Recording failed: \(error.localizedDescription)") }
    }

    private func stopRecording(_ r: Recorder) {
        recorder = nil
        audio?.onPCM = nil
        recordItem.title = "Start Recording"
        showFlash("Saving \(r.url.lastPathComponent)")
        r.finish { [weak self] in
            DispatchQueue.main.async {
                self?.showFlash("Saved \(r.url.lastPathComponent)")
                self?.recordingFinished?(r.url)
            }
        }
    }

    // MARK: Synergy switch

    /// Thin glue; the decisions live in SynergySwitch.isClickClearOfEdge and shouldSend.
    func switchSynergy(clickAt location: CGPoint) {
        guard SynergySwitch.isClickClearOfEdge(at: location, desktop: edgeGuard.desktop()) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard SynergySwitch.shouldSend(enabled: SynergySwitch.isEnabled(), trusted: accessibilityTrusted,
                                       lastSent: lastSwitch, now: now) else { return }
        lastSwitch = now
        performSwitch()
    }

    private func postEdgeCrossing() {
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

    func refreshStatus() {
        deskflow.poll()
        // The recording line sits above whatever else is shown, so a running recording is never hidden.
        let recording = recorder.map { _ in "Recording \(CaptureFile.clock(ProcessInfo.processInfo.systemUptime - recordingStartedAt))" }
        video.status = [recording, statusMessage()].compactMap { $0 }.joined(separator: "\n")
    }

    private func statusMessage() -> String {
        if let f = flash {
            if ProcessInfo.processInfo.systemUptime < f.until { return f.text }
            flash = nil
        }
        if let text = deskflow.overrideStatus { return text }
        if SynergySwitch.isEnabled() && !accessibilityTrusted { return SynergySwitch.untrustedStatus }
        let fps = fpsMeter.fps(at: Date.timeIntervalSinceReferenceDate)
        if let last = lastFrame, Date().timeIntervalSince(last) < 3 {
            let mode = client?.usingSnapshotFallback == true ? " (snapshot polling)" : ""
            return String(format: "%.0f FPS%@", fps, mode)
        }
        return lastFrame != nil ? "No signal" : baseStatus
    }

    // MARK: Window and menu

    func buildWindow() {
        // One window: no tab bar and no Show Tab Bar / Merge All Windows items in the menus.
        NSWindow.allowsAutomaticWindowTabbing = false
        window = NSWindow(contentRect: NSRect(origin: .zero, size: ViewGeometry.actualSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Amiga-View"
        window.contentView = video
        window.initialFirstResponder = video
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        if let name = frameAutosaveName {
            if !window.setFrameUsingName(name) { window.center() }
            window.setFrameAutosaveName(name)
        }
        applyPicture(resize: false)
        window.delegate = edgeGuard
        edgeGuard.apply(to: window)
        video.onEscape = { [weak self] in
            guard let self, self.isFullScreen() else { return }
            self.exitFullScreen()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterFullScreen),
                                               name: NSWindow.didEnterFullScreenNotification, object: window)
        window.level = defaults.bool(forKey: "alwaysOnTop") ? .floating : .normal
        window.makeKeyAndOrderFront(nil)
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Amiga-View", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Save Snapshot", action: #selector(saveSnapshot), keyEquivalent: "s").target = self
        recordItem = file.addItem(withTitle: recorder == nil ? "Start Recording" : "Stop Recording",
                                  action: #selector(toggleRecording), keyEquivalent: "r")
        recordItem.target = self
        fileItem.submenu = file

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Actual Size", action: #selector(actualSize), keyEquivalent: "1").target = self
        view.addItem(withTitle: "Double Size", action: #selector(doubleSize), keyEquivalent: "2").target = self
        view.addItem(.separator())
        alwaysOnTopItem = view.addItem(withTitle: "Always on Top", action: #selector(toggleOnTop), keyEquivalent: "t")
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = window.level == .floating ? .on : .off
        view.addItem(.separator())
        for (option, title) in [(PictureOption.cropOverscan, "Crop Overscan"), (.integerScaling, "Integer Scaling"),
                                (.scanlines, "Scanlines")] {
            let item = view.addItem(withTitle: title, action: #selector(togglePicture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = option.isEnabled(in: defaults) ? .on : .off
            pictureItems[option] = item
        }
        let fullScreen = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        view.addItem(.separator())
        synergyItem = view.addItem(withTitle: "Switch Synergy on Click", action: #selector(toggleSynergy), keyEquivalent: "")
        synergyItem.target = self
        synergyItem.state = SynergySwitch.isEnabled() ? .on : .off
        view.addItem(.separator())
        soundItem = view.addItem(withTitle: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = AudioStreamClient.isEnabled() ? .on : .off
        viewItem.submenu = view

        let amigaItem = NSMenuItem(); main.addItem(amigaItem)
        let amiga = NSMenu(title: "Amiga")
        amiga.addItem(withTitle: "Reset Amiga...", action: #selector(resetAmiga), keyEquivalent: "").target = self
        amigaItem.submenu = amiga
        NSApp.mainMenu = main
    }

    @objc private func actualSize() { window.setContentSize(ViewGeometry.size(scale: 1)) }
    @objc private func doubleSize() { window.setContentSize(ViewGeometry.size(scale: 2)) }

    /// Pushes the picture options into the view and the window's aspect ratio. A change of the
    /// crop keeps the window's width and follows the new aspect in height.
    private func applyPicture(resize: Bool = true) {
        let crop = currentCrop
        video.crop = crop
        video.integerScaling = PictureOption.integerScaling.isEnabled(in: defaults)
        video.scanlines = PictureOption.scanlines.isEnabled(in: defaults)
        let size = ViewGeometry.displaySize(of: crop)
        window.contentAspectRatio = size
        window.contentMinSize = NSSize(width: size.width / 2, height: size.height / 2)
        if resize, !window.styleMask.contains(.fullScreen) {
            let width = window.contentRect(forFrameRect: window.frame).width
            window.setContentSize(NSSize(width: width, height: width * size.height / size.width))
        }
    }

    @objc private func togglePicture(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? PictureOption else { return }
        let on = !option.isEnabled(in: defaults)
        option.setEnabled(on, in: defaults)
        sender.state = on ? .on : .off
        applyPicture()
    }

    @objc private func toggleSynergy() {
        let on = !SynergySwitch.isEnabled()
        SynergySwitch.setEnabled(on)
        synergyItem.state = on ? .on : .off
    }

    @objc private func toggleSound() {
        let on = !AudioStreamClient.isEnabled()
        AudioStreamClient.setEnabled(on)
        soundItem.state = on ? .on : .off
        if on { startAudio() } else { stopAudio() }
    }

    @objc private func toggleOnTop() {
        let on = window.level != .floating
        window.level = on ? .floating : .normal
        alwaysOnTopItem.state = on ? .on : .off
        defaults.set(on, forKey: "alwaysOnTop")
    }
}
