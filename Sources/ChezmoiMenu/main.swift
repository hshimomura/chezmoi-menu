import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var item: NSStatusItem!
    private var window: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // LaunchServices normally reuses the existing app; also guard direct executable launches.
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "jp.local.ChezmoiMenu")
        if siblings.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        installMainMenu()
        NSApp.applicationIconImage = BrandIcon.application
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        model.$running.combineLatest(model.$status).sink { [weak self] running, status in
            self?.updateMenu(running: running, status: status)
        }.store(in: &subscriptions)
        updateMenu(running: false, status: model.status)
        if !FileManager.default.fileExists(atPath: model.support.appendingPathComponent("settings.json").path) {
            showSettings()
        }
    }

    private func installMainMenu() {
        let main = NSMenu()
        let application = NSMenu()
        let appRoot = NSMenuItem(); appRoot.submenu = application; main.addItem(appRoot)
        let preferences = application.addItem(withTitle: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        preferences.target = self
        application.addItem(.separator())
        let quit = application.addItem(withTitle: "Chezmoi Menu を終了", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        let edit = NSMenu(title: "編集")
        let editRoot = NSMenuItem(); editRoot.submenu = edit; main.addItem(editRoot)
        edit.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "切り取る", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowMenu = NSMenu(title: "ウインドウ")
        let windowRoot = NSMenuItem(); windowRoot.submenu = windowMenu; main.addItem(windowRoot)
        windowMenu.addItem(withTitle: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    private func updateMenu(running: Bool, status: String) {
        item.button?.image = running
            ? NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "同期中")
            : BrandIcon.menuBar
        item.button?.toolTip = "Chezmoi Menu — \(status)"
        let menu = NSMenu()
        let title = menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(.separator())
        let download = menu.addItem(withTitle: "↓ Download 同期", action: #selector(downloadSync), keyEquivalent: "d")
        download.target = self; download.isEnabled = !running
        let upload = menu.addItem(withTitle: "↑ Upload 同期", action: #selector(uploadSync), keyEquivalent: "u")
        upload.target = self; upload.isEnabled = !running
        let check = menu.addItem(withTitle: "同期前チェック（適用・送信なし）", action: #selector(checkSync), keyEquivalent: "t")
        check.target = self; check.isEnabled = !running
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "設定・実行履歴…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let backups = menu.addItem(withTitle: "バックアップを開く…", action: #selector(showBackups), keyEquivalent: "")
        backups.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "終了", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; quit.isEnabled = !running
        menu.autoenablesItems = false
        item.menu = menu
    }
    @objc private func downloadSync() { model.start(.download) }
    @objc private func uploadSync() { model.start(.upload) }
    @objc private func checkSync() { model.check() }
    @objc private func showBackups() { model.openBackups() }
    @objc private func quitApp() { if !model.running { NSApp.terminate(nil) } }
    @objc func showSettings() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.title = "Chezmoi Menu"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.running ? .terminateCancel : .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
