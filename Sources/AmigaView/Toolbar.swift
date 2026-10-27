import AppKit
import AmigaViewCore

extension NSToolbarItem.Identifier {
    static let snapshot = Self("snapshot")
    static let record = Self("record")
    static let sound = Self("sound")
    static let fullScreen = Self("fullScreen")
    static let resetAmiga = Self("resetAmiga")
    static let settings = Self("settings")
    static let frameRate = Self("frameRate")
}

/// The window's toolbar: buttons for the actions people reach for most, each running the same
/// action as its menu item. View > Hide Toolbar hides it, and the system remembers that. In full
/// screen it hides with the menu bar (see EdgeGuard), so only the picture shows.
extension AppDelegate: NSToolbarDelegate {
    static let toolbarItems: [NSToolbarItem.Identifier] = [.snapshot, .record, .sound, .fullScreen, .flexibleSpace, .frameRate, .flexibleSpace, .resetAmiga, .settings]

    func buildToolbar() {
        // A new identifier whenever the items change: the autosaved configuration lists the items
        // of the old one, so a new item would not appear.
        let toolbar = NSToolbar(identifier: "main.2")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        updateToolbar()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.toolbarItems }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.toolbarItems }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.target = self
        item.isBordered = true
        switch id {
        case .snapshot: set(item, "Save Snapshot", "camera", #selector(saveSnapshot))
        case .record: set(item, "Start Recording", "record.circle", #selector(toggleRecording))
        case .sound: set(item, "Sound", "speaker.wave.2", #selector(toggleSound))
        case .fullScreen:
            set(item, "Enter Full Screen", "arrow.up.left.and.arrow.down.right", #selector(NSWindow.toggleFullScreen(_:)))
            item.target = nil
        case .resetAmiga: set(item, "Reset Amiga", "power", #selector(resetAmiga))
        case .settings: set(item, "Settings", "gearshape", #selector(openSettings))
        case .frameRate:
            item.label = "Frame Rate"
            item.paletteLabel = "Frame Rate"
            item.toolTip = "Frame Rate"
            item.isBordered = false
            let field = NSTextField(labelWithString: frameRateText())
            field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            field.textColor = .secondaryLabelColor
            item.view = field
        default: return nil
        }
        return item
    }

    private func set(_ item: NSToolbarItem, _ label: String, _ symbol: String, _ action: Selector) {
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.action = action
    }

    /// Shows the recording and sound state on their buttons.
    func updateToolbar() {
        for item in window.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case .record:
                let on = recorder != nil
                set(item, on ? "Stop Recording" : "Start Recording", on ? "stop.circle" : "record.circle", #selector(toggleRecording))
            case .sound:
                let on = AudioStreamClient.isEnabled()
                set(item, on ? "Sound" : "Sound Off", on ? "speaker.wave.2" : "speaker.slash", #selector(toggleSound))
            default: break
            }
        }
    }

    func updateFrameRateItem() {
        let item = window.toolbar?.items.first { $0.itemIdentifier == .frameRate }
        (item?.view as? NSTextField)?.stringValue = frameRateText()
    }
}
