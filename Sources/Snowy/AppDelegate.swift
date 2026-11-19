import AppKit
import SnowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSMenuDelegate {
    private var coordinator: DesktopCoordinator?
    private var statusItem: NSStatusItem?
    private let pauseItem = NSMenuItem(title: "Pause Snow", action: #selector(togglePause), keyEquivalent: "p")
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let thawItem = NSMenuItem(title: "Thaw Settled Snow", action: #selector(thawSnow), keyEquivalent: "t")
    private let clearItem = NSMenuItem(title: "Clear Settled Snow", action: #selector(clearSnow), keyEquivalent: "k")
    private var seasonItems: [NSMenuItem] = []
    private var weatherItems: [NSMenuItem] = []
    private var windPopover: NSPopover?
    private var toolItems: [NSMenuItem] = []
    private var welcomeWindow: WelcomeWindowController?
    private var snowyWindow: SnowyWindowController?
    private let decorationSettings = DecorationSettings()
    private let updater = SnowyUpdater()
    private let updateItem = NSMenuItem(title: "Update", action: #selector(installUpdate), keyEquivalent: "")
    private var updateCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read the persisted domain before coordinator startup can write settings.
        let defaults = UserDefaults.standard
        let domainName = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let shouldShowWelcome = FirstLaunchPolicy.shouldPresent(in: defaults, domainName: domainName)
        buildMenu()
        updater.onChange = { [weak self] in self?.updateAvailableRelease() }
        updater.start()

        let timer = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updater.probeForUpdates()
                // The calendar may have crossed into a new season while the app stayed open.
                self?.coordinator?.refreshSeason()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateCheckTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updater.probeForUpdates() }
        }
        do {
            let coordinator = try DesktopCoordinator()
            self.coordinator = coordinator
            coordinator.onStateChange = { [weak self] in self?.updateMenu() }
            decorationSettings.onChange = { [weak coordinator] configuration in
                coordinator?.setDecorations(configuration)
            }
            decorationSettings.desktops = coordinator.editorDesktops
            decorationSettings.onEditorVisibility = { [weak coordinator] visible in
                coordinator?.setEditorVisible(visible)
            }
            coordinator.onDesktopGeometryChange = { [weak self] desktops in
                self?.decorationSettings.desktops = desktops
            }
            decorationSettings.apply()
        } catch {
            stateItem.title = "Metal is unavailable on this Mac"
            pauseItem.isEnabled = false
            thawItem.isEnabled = false
        }
        updateMenu()
        if coordinator != nil {
            FirstLaunchPolicy.markConsidered(in: defaults)
            if shouldShowWelcome { presentWelcome() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let welcomeWindow { welcomeWindow.present() }
        else { presentSnowyWindow() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil
        welcomeWindow?.close()
        snowyWindow?.close()
        windPopover?.performClose(nil)
        coordinator?.stop()
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Seasons")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Seasons — desktop snowfall"
        statusItem = item
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let support = NSMenuItem(title: "Drop some coins", action: #selector(openSupportCheckout), keyEquivalent: "")
        support.target = self
        menu.addItem(support)
        menu.addItem(.separator())
        let title = NSMenuItem(title: "Seasons", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Seasons…", action: #selector(openSnowyWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        pauseItem.target = self
        menu.addItem(pauseItem)
        clearItem.target = self
        menu.addItem(clearItem)
        thawItem.target = self
        menu.addItem(thawItem)
        let tool = NSMenuItem(title: "Cursor Tool", action: nil, keyEquivalent: "")
        let tools = NSMenu(title: "Cursor Tool")
        tools.autoenablesItems = false
        for (index, name) in ["Glove", "Shovel", "Leaf Blower"].enumerated() {
            let option = NSMenuItem(title: name, action: #selector(selectTool(_:)), keyEquivalent: "")
            option.tag = index
            option.target = self
            tools.addItem(option)
            toolItems.append(option)
        }
        tool.submenu = tools
        menu.addItem(tool)
        let season = NSMenuItem(title: "Season", action: nil, keyEquivalent: "")
        let seasons = NSMenu(title: "Season")
        seasons.autoenablesItems = false
        for (index, name) in (["Follow the Calendar"] + Season.allCases.map(\.rawValue)).enumerated() {
            let option = NSMenuItem(title: name, action: #selector(selectSeason(_:)), keyEquivalent: "")
            option.tag = index
            option.target = self
            seasons.addItem(option)
            seasonItems.append(option)
            if index == 0 { seasons.addItem(.separator()) }
        }
        season.submenu = seasons
        menu.addItem(season)
        menu.addItem(.separator())
        for (index, snowfall) in Snowfall.allCases.enumerated() {
            let option = NSMenuItem(title: snowfall.rawValue, action: #selector(setSnowfall(_:)), keyEquivalent: "")
            option.target = self
            option.tag = index
            weatherItems.append(option)
            menu.addItem(option)
        }
        let wind = NSMenuItem(title: "Wind…", action: #selector(showWind), keyEquivalent: "w")
        wind.target = self
        menu.addItem(wind)
        menu.addItem(.separator())
        updateItem.target = self
        updateItem.isHidden = true
        updateItem.isEnabled = false
        menu.addItem(updateItem)
        let quit = NSMenuItem(title: "Quit Seasons", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateAvailableRelease()
        updater.probeForUpdates()
    }

    private func updateAvailableRelease() {
        guard let version = updater.availableVersion else {
            updateItem.isHidden = true
            return
        }
        updateItem.attributedTitle = NSAttributedString(
            string: "Update to \(version)…",
            attributes: [.foregroundColor: NSColor.linkColor]
        )
        updateItem.isHidden = false
        updateItem.isEnabled = updater.canInstall
    }

    @objc private func installUpdate() { updater.install() }

    @objc private func openSnowyWindow() {
        DispatchQueue.main.async { [weak self] in self?.presentSnowyWindow() }
    }

    private func presentSnowyWindow() {
        updater.probeForUpdates()
        if snowyWindow == nil {
            snowyWindow = SnowyWindowController(
                settings: decorationSettings,
                updater: updater,
                resetDecorations: { [weak self] in self?.coordinator?.resetDecorations() },
                replayWalkthrough: { [weak self] in self?.presentWelcome() }
            )
        }
        snowyWindow?.present()
    }

    private func presentWelcome() {
        if welcomeWindow == nil {
            let welcome = WelcomeWindowController()
            welcome.onClose = { [weak self] in self?.welcomeWindow = nil }
            welcomeWindow = welcome
        }
        welcomeWindow?.present()
    }

    @objc private func openSupportCheckout() {
        guard let url = URL(string: "https://snowy.aauburn.com/#drop-some-coins") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateMenu() {
        guard let coordinator else { return }
        let fall = coordinator.season == .fall
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: fall ? "leaf.fill" : "snowflake", accessibilityDescription: "Seasons")
            button.image?.isTemplate = true
            button.toolTip = fall ? "Seasons — falling leaves" : "Seasons — desktop snowfall"
        }
        for (index, item) in seasonItems.enumerated() {
            item.state = (index == 0 ? coordinator.seasonChoice == nil
                          : coordinator.seasonChoice == Season.allCases[index - 1]) ? .on : .off
        }
        if toolItems.count == 3 {
            toolItems[1].title = fall ? "Rake" : "Shovel"
            toolItems[2].isHidden = !fall
            toolItems[2].state = coordinator.tool == .blower ? .on : .off
        }
        clearItem.title = fall ? "Clear Fallen Leaves" : "Clear Settled Snow"
        thawItem.title = fall ? "Let Leaves Blow Away" : "Thaw Settled Snow"
        guard !fall else {
            pauseItem.title = coordinator.paused ? "Resume Leaves" : "Pause Leaves"
            thawItem.isEnabled = coordinator.canThaw
            if coordinator.failed { stateItem.title = "Rendering stopped — relaunch to retry" }
            else if coordinator.policy.suspended { stateItem.title = "Resting while your Mac cools down" }
            else if coordinator.paused { stateItem.title = "Leaves are paused" }
            else if coordinator.policy.reducedMotion { stateItem.title = "Quiet piles · Reduce Motion" }
            else if coordinator.policy.particleScale < 1 { stateItem.title = "Fewer leaves · saving energy" }
            else if coordinator.tool == .blower { stateItem.title = "Sweep the pointer past a pile to blow it away" }
            else { stateItem.title = "Brush a leafy edge to scatter it" }
            for (index, item) in weatherItems.enumerated() {
                item.state = Snowfall.allCases[index] == coordinator.snowfall ? .on : .off
            }
            toolItems.first?.state = coordinator.tool == .glove ? .on : .off
            if toolItems.count > 1 { toolItems[1].state = coordinator.tool == .shovel ? .on : .off }
            return
        }
        pauseItem.title = coordinator.paused ? "Resume Snow" : "Pause Snow"
        // A thaw melts on the running snow clock, so it is unavailable while that is stopped.
        thawItem.isEnabled = coordinator.canThaw
        if coordinator.failed { stateItem.title = "Rendering stopped — relaunch to retry" }
        else if coordinator.policy.suspended { stateItem.title = "Resting while your Mac cools down" }
        else if coordinator.paused { stateItem.title = "Snow is paused" }
        else if coordinator.policy.reducedMotion { stateItem.title = "Quiet drifts · Reduce Motion" }
        else if coordinator.policy.particleScale < 1 { stateItem.title = "Gentle snowfall · saving energy" }
        else { stateItem.title = "Brush a snowy edge to sweep it away" }
        for (index, item) in weatherItems.enumerated() {
            item.state = Snowfall.allCases[index] == coordinator.snowfall ? .on : .off
        }
        for (index, item) in toolItems.prefix(2).enumerated() {
            item.state = (index == 1 ? coordinator.tool == .shovel : coordinator.tool == .glove) ? .on : .off
        }
    }

    @objc private func togglePause() { coordinator?.paused.toggle() }
    @objc private func clearSnow() { coordinator?.clear() }
    @objc private func thawSnow() { coordinator?.thaw() }
    @objc private func showWind() {
        // A menu action runs during tracking; show after it closes so the popover receives focus.
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem?.button, let coordinator = self.coordinator else { return }
            if let popover = self.windPopover, popover.isShown { popover.performClose(nil); return }
            let content = WindViewController()
            content.settings = coordinator.wind
            content.onChange = { [weak coordinator] value in coordinator?.wind = value }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            popover.contentViewController = content
            popover.delegate = self
            content.onClose = { [weak popover] in popover?.performClose(nil) }
            self.windPopover = popover
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === windPopover else { return }
        windPopover = nil
    }

    @objc private func selectTool(_ sender: NSMenuItem) {
        coordinator?.tool = sender.tag == 2 ? .blower : (sender.tag == 1 ? .shovel : .glove)
    }
    @objc private func selectSeason(_ sender: NSMenuItem) {
        coordinator?.seasonChoice = Season.allCases.indices.contains(sender.tag - 1) ? Season.allCases[sender.tag - 1] : nil
        updateMenu()
    }
    @objc private func setSnowfall(_ sender: NSMenuItem) {
        guard Snowfall.allCases.indices.contains(sender.tag) else { return }
        coordinator?.snowfall = Snowfall.allCases[sender.tag]
    }
}
