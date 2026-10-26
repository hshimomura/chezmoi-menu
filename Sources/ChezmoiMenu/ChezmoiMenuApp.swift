import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "jp.local.ChezmoiMenu")
        if siblings.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.running ? .terminateCancel : .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.show(); return true
    }
}

@main
struct ChezmoiMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra { MenuPanel(model: model) } label: { MenuLabel(model: model) }
            .menuBarExtraStyle(.window)
        Window("Chezmoi Menu", id: "main") { SettingsView(model: model) }
            .defaultSize(width: 840, height: 660)
            .defaultLaunchBehavior(.suppressed)
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("設定…") { model.show(.general) }.keyboardShortcut(",")
                }
            }
    }
}

private struct MenuLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(nsImage: BrandIcon.menuBar)
            .symbolEffect(.pulse, isActive: model.running)
            .help("Chezmoi Menu — \(model.status)")
            .onChange(of: model.windowRequest) {
                openWindow(id: "main")
                NSApp.activate()
            }
            .task {
                if !FileManager.default.fileExists(atPath: model.support.appendingPathComponent("settings.json").path) {
                    model.show(.general)
                }
            }
    }
}

struct OperationStatus: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.stopping ? "停止を待機しています…" : model.running ? model.phase.title : "Chezmoi Menu")
                    .font(.headline)
                Spacer()
                if model.running { ProgressView().controlSize(.small) }
            }
            Text(model.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.running {
                ProgressView(value: model.phase.progress).accessibilityLabel("\(model.phase.title)の段階")
                HStack {
                    Text(model.stopping ? "変更中の処理を完了し、後処理して停止します。" : "進捗は処理の段階を表しています。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("停止", role: .cancel) { model.cancel() }.disabled(model.stopping)
                }
            }
        }
    }
}

struct SyncButtons: View {
    let model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            Button { model.start(.download) } label: {
                Label("Download", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
            }
            Button { model.start(.upload) } label: {
                Label("Upload", systemImage: "arrow.up.circle").frame(maxWidth: .infinity)
            }
        }.buttonStyle(.glass).controlSize(.large).disabled(model.running)
    }
}

private struct MenuPanel: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OperationStatus(model: model)
            SyncButtons(model: model)
            HStack {
                Button("同期前チェック", systemImage: "checkmark.shield") { model.start(.check) }.disabled(model.running)
                Spacer()
                Button("差分", systemImage: "doc.text.magnifyingglass") { model.show(.diff) }
            }
            if let result = model.checkReport {
                Text("管理対象 \(result.managedCount) 件 · Mac との差分 \(result.destinationChanges) 件")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.notice.isEmpty {
                Text(model.notice).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                Button("詳細を確認") { model.show(.history) }
            }
            Divider()
            HStack {
                Button("設定", systemImage: "gearshape") { model.show(.general) }
                Button("履歴", systemImage: "clock") { model.show(.history) }
                Spacer()
                Button("終了") { NSApp.terminate(nil) }.disabled(model.running)
            }.buttonStyle(.borderless)
        }.padding(22).frame(width: 370)
    }
}
