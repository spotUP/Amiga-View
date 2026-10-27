import AppKit
import AmigaViewCore

/// Amiga-View > Settings...: where the Amiga's wasabid listens, and the key it checks. The key is
/// never shown: a typed key goes to the Keychain, and an empty field keeps the stored one.
final class SettingsWindowController: NSWindowController {
    let hostField = NSTextField()
    let portField = NSTextField()
    let keyField = NSSecureTextField()
    let keyFileField = NSTextField()
    let keyStatus = NSTextField(wrappingLabelWithString: "")
    let errorLabel = NSTextField(labelWithString: "")
    let saveButton = NSButton(title: "Save", target: nil, action: nil)
    let forgetButton = NSButton(title: "Forget Stored Key", target: nil, action: nil)
    private let defaults: UserDefaults
    private let keychain: Keychain
    /// Runs after a successful save.
    var saved: (() -> Void)?

    init(defaults: UserDefaults, keychain: Keychain) {
        self.defaults = defaults
        self.keychain = keychain
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 10), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        load()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        hostField.placeholderString = AmigaReset.defaults.host
        portField.placeholderString = String(AmigaReset.defaults.port)
        keyFileField.placeholderString = AmigaReset.defaults.keyFile
        for f in [hostField, portField, keyField, keyFileField] { f.widthAnchor.constraint(equalToConstant: 300).isActive = true }
        keyStatus.textColor = .secondaryLabelColor
        keyStatus.preferredMaxLayoutWidth = 300
        let fileNote = NSTextField(wrappingLabelWithString: "Used when no key is stored. UP-Term writes this file when it installs wasabid on the Amiga.")
        fileNote.textColor = .secondaryLabelColor
        fileNote.preferredMaxLayoutWidth = 300
        errorLabel.textColor = .systemRed

        let label = { (text: String) in NSTextField(labelWithString: text) }
        let grid = NSGridView(views: [
            [label("Amiga address:"), hostField],
            [label("Port:"), portField],
            [label("wasabid key:"), keyField],
            [NSGridCell.emptyContentView, keyStatus],
            [label("Key file:"), keyFileField],
            [NSGridCell.emptyContentView, fileNote],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8

        forgetButton.target = self; forgetButton.action = #selector(forgetKey(_:))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self; saveButton.action = #selector(save(_:))
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [forgetButton, NSView(), cancel, saveButton])
        buttons.distribution = .fill

        let stack = NSStackView(views: [grid, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        window?.contentView = stack
    }

    /// Fills the fields from the stored settings; the key field always starts empty.
    func load() {
        let settings = AmigaReset.load(from: defaults, keychain: keychain)
        hostField.stringValue = settings.host
        portField.stringValue = String(settings.port)
        keyFileField.stringValue = settings.keyFile
        keyField.stringValue = ""
        errorLabel.stringValue = ""
        updateKeyStatus()
    }

    private func updateKeyStatus() {
        let stored = keychain.read() != nil
        keyField.placeholderString = stored ? "Stored in the Keychain" : "Not set"
        keyStatus.stringValue = stored ? "A key is stored in the Keychain. Leave the field empty to keep it."
                                       : "No key is stored; the key file below is used."
        forgetButton.isEnabled = stored
    }

    @objc func save(_ sender: Any?) {
        switch AmigaReset.parse(host: hostField.stringValue, port: portField.stringValue,
                                keyFile: keyFileField.stringValue, keychain: keychain) {
        case .failure(let error):
            errorLabel.stringValue = error.message
        case .success(let settings):
            let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, let status = keychain.write(key) {
                errorLabel.stringValue = "Could not store the key in the Keychain (error \(status))"
                return
            }
            settings.save(to: defaults)
            keyField.stringValue = ""
            close()
            saved?()
        }
    }

    @objc func forgetKey(_ sender: Any?) {
        keychain.delete()
        updateKeyStatus()
    }

    @objc func cancel(_ sender: Any?) { close() }
}
