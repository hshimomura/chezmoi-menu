import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: BrandIcon.application)
                    .resizable().interpolation(.high)
                    .frame(width: 56, height: 56)
                    .accessibilityLabel("Chezmoi Menu")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chezmoi Menu").font(.title2.bold())
                    Text("Mac の設定を、メニューバーから同期。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.running { ProgressView().controlSize(.small) }
            }
            HStack {
                Label(model.status, systemImage: model.running ? "arrow.triangle.2.circlepath" : "circle.fill")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
            }
            HStack(spacing: 12) {
                Button { model.start(.download) } label: {
                    Label("Download 同期", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                }
                Button { model.start(.upload) } label: {
                    Label("Upload 同期", systemImage: "arrow.up.circle").frame(maxWidth: .infinity)
                }
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.running)
            Button { model.check() } label: {
                Label("同期前チェック（適用・送信なし）", systemImage: "checkmark.shield")
            }.disabled(model.running)
            TabView {
                settings.tabItem { Label("設定", systemImage: "gearshape") }
                VStack(alignment: .leading, spacing: 10) {
                    Text("ファイルの内容・API key は履歴に記録しません。")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        Text(model.history.reversed().joined(separator: "\n\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("バックアップを Finder で開く") { model.openBackups() }
                }.padding().tabItem { Label("実行履歴", systemImage: "clock") }
            }
            if !model.notice.isEmpty {
                Text(model.notice).font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(24).frame(width: 640, height: 690)
    }

    private var settings: some View {
        Form {
            Section("chezmoi") {
                TextField("実行ファイル", text: $model.settings.chezmoiPath)
                TextField("設定ファイル（空欄で既定値）", text: $model.settings.configPath)
                Text("既存の source・destination と現在のブランチの upstream を使用します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("OpenAI による競合解決") {
                SecureField("API key（空欄で保存済みキーを保持）", text: $model.apiKey)
                    .textContentType(.password)
                TextField("モデル", text: $model.settings.model)
                Toggle("競合を自動解決する", isOn: $model.settings.autoResolve)
                Text("競合ファイルの共通祖先・ローカル版・リモート版を OpenAI API に送信します。API 料金が発生します。解決できない場合は停止します。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("AI 送信の除外パス（部分一致・1 行に 1 件）") {
                    TextEditor(text: $model.settings.excludedAIPaths)
                        .font(.system(.caption, design: .monospaced)).frame(height: 78)
                    Text("暗号化ファイルは除外設定にかかわらず自動解決しません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("動作") {
                Toggle("chezmoi のスクリプトも適用する", isOn: $model.settings.runScripts)
                Toggle("ログイン時に起動する", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                Text("Download でもローカルの変更を退避するためコミットします。リモートへの送信は Upload のみです。バックアップは自動削除しません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("設定を保存") { model.save() }.buttonStyle(.borderedProminent)
        }.formStyle(.grouped).disabled(model.running)
    }
}
