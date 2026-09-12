import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var multitouchManager: MultitouchManager?
    var isEnabled = true
    private var hasStartedMultitouch = false
    private var hasRequestedAccessibilityPrompt = false
    private var hasShownAccessibilityInstructions = false
    private var deviceReconnectMonitor: DeviceReconnectMonitor?
    private var connectionStatusItem: NSMenuItem?
    private var enabledMenuItem: NSMenuItem?
    private var isMagicMouseConnected = false
    private var clickSequenceTracker = ClickSequenceTracker(
        interval: NSEvent.doubleClickInterval,
        movementThreshold: 5.0
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        ensureAccessibilityAndStart()
    }

    @objc func showAccessibilityInstructions() {
        guard !hasShownAccessibilityInstructions else { return }
        hasShownAccessibilityInstructions = true
        let alert = NSAlert()
        alert.messageText = L10n.string(.accessibilityRequired)
        alert.informativeText = L10n.accessibilityDetail()
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string(.openSystemSettings))
        alert.addButton(withTitle: L10n.string(.close))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        hasShownAccessibilityInstructions = false
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        deviceReconnectMonitor?.stop()
        multitouchManager?.stop()
    }

    func setupMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "Mouse Toucher")
            }
        }

        let menu = NSMenu()

        let mouseStatusItem = buildMouseConnectionStatusItem()
        connectionStatusItem = mouseStatusItem
        menu.addItem(mouseStatusItem)

        menu.addItem(NSMenuItem.separator())

        let enabledItem = NSMenuItem(
            title: isEnabled ? L10n.string(.tapEnabled) : L10n.string(.tapDisabled),
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = isEnabled ? .on : .off
        enabledMenuItem = enabledItem
        menu.addItem(enabledItem)
        menu.addItem(buildRightClickZoneItem())

        menu.addItem(NSMenuItem.separator())
        let accessibilityItem = NSMenuItem(title: L10n.string(.accessibilityInstructions), action: #selector(showAccessibilityInstructions), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(buildLanguageItem())
        let aboutItem = NSMenuItem(title: L10n.string(.about), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: L10n.string(.quit), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func buildMouseConnectionStatusItem() -> NSMenuItem {
        let key: L10n.Key = isMagicMouseConnected ? .mouseConnected : .mouseDisconnected
        let item = NSMenuItem(title: L10n.string(key), action: nil, keyEquivalent: "")
        item.image = NSImage(
            systemSymbolName: isMagicMouseConnected ? "checkmark.circle.fill" : "xmark.circle",
            accessibilityDescription: L10n.string(key)
        )
        item.isEnabled = false
        return item
    }

    private func updateMouseConnectionStatus(_ isConnected: Bool) {
        isMagicMouseConnected = isConnected
        let key: L10n.Key = isConnected ? .mouseConnected : .mouseDisconnected
        connectionStatusItem?.title = L10n.string(key)
        connectionStatusItem?.image = NSImage(
            systemSymbolName: isConnected ? "checkmark.circle.fill" : "xmark.circle",
            accessibilityDescription: L10n.string(key)
        )
    }

    @objc func toggleEnabled() {
        isEnabled.toggle()
        enabledMenuItem?.state = isEnabled ? .on : .off
        enabledMenuItem?.title = isEnabled ? L10n.string(.tapEnabled) : L10n.string(.tapDisabled)
        multitouchManager?.setEnabled(isEnabled)
    }

    /// Submenu letting the user pick where the left/right click boundary sits on the mouse surface.
    private func buildRightClickZoneItem() -> NSMenuItem {
        let parentItem = NSMenuItem(title: L10n.string(.rightClickZone), action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        var choices = Preferences.rightClickThresholdChoices
        let current = Preferences.rightClickThreshold
        // Surface a value set outside the app (e.g. via `defaults write`) so it's still selectable.
        if !choices.contains(current) {
            choices.append(current)
            choices.sort()
        }

        for choice in choices {
            let percent = Int((choice * 100).rounded())
            let item = NSMenuItem(
                title: L10n.rightSideStarts(at: percent),
                action: #selector(selectRightClickThreshold(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = choice
            item.state = choice == current ? .on : .off
            submenu.addItem(item)
        }

        parentItem.submenu = submenu
        return parentItem
    }

    private func buildLanguageItem() -> NSMenuItem {
        let parentItem = NSMenuItem(title: L10n.string(.language), action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for language in AppLanguage.allCases {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == Preferences.appLanguage ? .on : .off
            submenu.addItem(item)
        }

        parentItem.submenu = submenu
        return parentItem
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else { return }

        Preferences.appLanguage = language
        setupMenuBar()
    }

    @objc func selectRightClickThreshold(_ sender: NSMenuItem) {
        guard let threshold = sender.representedObject as? Float else { return }

        Preferences.rightClickThreshold = threshold
        multitouchManager?.rightClickThreshold = Preferences.rightClickThreshold

        guard let submenu = sender.menu else { return }
        for item in submenu.items {
            item.state = (item.representedObject as? Float) == Preferences.rightClickThreshold ? .on : .off
        }
    }

    @objc func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let alert = NSAlert()
        alert.messageText = L10n.string(.about)
        alert.informativeText = """
        \(L10n.string(.tapToClickSubtitle))

        • \(L10n.string(.leftTapHelp))
        • \(L10n.string(.rightTapHelp))

        \(L10n.string(.maintainer))

        \(L10n.string(.projectURL))

        \(L10n.string(.version)) \(version)

        \(L10n.string(.privateFrameworkNotice))
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.string(.ok))
        alert.runModal()
    }

    @objc func quit() {
        multitouchManager?.stop()
        NSApplication.shared.terminate(nil)
    }

    private func ensureAccessibilityAndStart() {
        if AXIsProcessTrusted() {
            startMultitouchManager()
            return
        }

        requestAccessibilityPermissionIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard !AXIsProcessTrusted() else { return }
            self?.showAccessibilityInstructions()
        }
        waitForAccessibilityPermission()
    }

    private func startMultitouchManager() {
        guard !hasStartedMultitouch else { return }
        hasStartedMultitouch = true

        multitouchManager = MultitouchManager()
        multitouchManager?.onClickSynthesized = { [weak self] location, isRightClick in
            self?.synthesizeClick(at: location, isRightClick: isRightClick)
        }
        multitouchManager?.onConnectionStatusChanged = { [weak self] isConnected in
            DispatchQueue.main.async {
                self?.updateMouseConnectionStatus(isConnected)
            }
        }
        multitouchManager?.start()

        deviceReconnectMonitor = DeviceReconnectMonitor { [weak self] in
            self?.multitouchManager?.restart()
        }
        deviceReconnectMonitor?.start()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !hasRequestedAccessibilityPrompt else { return }
        hasRequestedAccessibilityPrompt = true

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func waitForAccessibilityPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            if AXIsProcessTrusted() {
                self.startMultitouchManager()
            } else {
                self.waitForAccessibilityPermission()
            }
        }
    }

    /// True if the point falls on an active display. Coordinates here are in Quartz global
    /// space (origin top-left), which is what `CGEvent.location` reports — so this must not be
    /// compared against `NSScreen.frame`, which uses Cocoa's bottom-left origin.
    private func isOnActiveDisplay(_ location: CGPoint) -> Bool {
        guard location.x.isFinite, location.y.isFinite else { return false }

        var matchingDisplayCount: UInt32 = 0
        // Fail open: if the query itself fails, don't silently swallow the click.
        guard CGGetDisplaysWithPoint(location, 0, nil, &matchingDisplayCount) == .success else {
            return true
        }
        return matchingDisplayCount > 0
    }

    func synthesizeClick(at location: CGPoint, isRightClick: Bool) {
        guard isOnActiveDisplay(location) else { return }

        let clickCount = clickSequenceTracker.registerClick(
            at: location,
            isRightClick: isRightClick,
            time: ProcessInfo.processInfo.systemUptime
        )

        if isRightClick {
            if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: location, mouseButton: .right) {
                mouseDown.setIntegerValueField(.mouseEventClickState, value: clickCount)
                mouseDown.post(tap: .cghidEventTap)
            }
            if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: location, mouseButton: .right) {
                mouseUp.setIntegerValueField(.mouseEventClickState, value: clickCount)
                mouseUp.post(tap: .cghidEventTap)
            }
        } else {
            if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left) {
                mouseDown.setIntegerValueField(.mouseEventClickState, value: clickCount)
                mouseDown.post(tap: .cghidEventTap)
            }
            if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left) {
                mouseUp.setIntegerValueField(.mouseEventClickState, value: clickCount)
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }
}
