import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $model.section) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 9) {
                    Image(nsImage: BrandIcon.application).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading) {
                        Text("Chezmoi Menu").font(.caption.bold())
                        Text("macOS 27 · Apple Silicon").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding()
            }
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch model.section {
                    case .overview: overview
                    case .general: general
                    case .ai: ai
                    case .diff: diff
                    case .history: history
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.notice.isEmpty {
                    Divider()
                    Text(model.notice).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }.navigationTitle(model.section.rawValue)
        }.frame(minWidth: 720, minHeight: 560)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OperationStatus(model: model)
                SyncButtons(model: model)
                Text("Download はリモートを取り込み、Mac に適用します。Upload は統合・適用後にリモートへ送信します。どちらも先にローカルの変更を保存します。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("同期前チェック", systemImage: "checkmark.shield") { model.start(.check) }.disabled(model.running)
                    Button("差分を確認", systemImage: "doc.text.magnifyingglass") { model.section = .diff }
                }
                if let result = model.checkReport {
                    GroupBox("チェック結果") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("管理対象", value: "\(result.managedCount) 件")
                            LabeledContent("source の変更", value: "\(result.sourceChanges) 件")
                            LabeledContent("Mac との差分", value: "\(result.destinationChanges) 件")
                            LabeledContent("リモートと HEAD", value: result.remoteMatches ? "一致" : "異なる")
                            Text("source: \(result.source)\n適用先: \(result.destination)")
                                .font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
                        }.padding(8)
                    }
                }
                Button("バックアップを開く", systemImage: "folder") { model.openBackups() }
            }.padding(28)
        }
    }

    private var general: some View {
        Form {
            Section("chezmoi") {
                TextField("実行ファイル", text: $model.settings.chezmoiPath)
                TextField("設定ファイル", text: $model.settings.configPath, prompt: Text("空欄で既定値"))
                Text("既存の source・destination と現在のブランチの upstream を使用します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("動作") {
                Toggle("chezmoi のスクリプトも適用する", isOn: $model.settings.runScripts)
                Toggle("ログイン時に起動する", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                Text("Download でもローカルの変更を保存するためコミットします。バックアップは自動削除しません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("設定を保存") { model.save() }.buttonStyle(.glassProminent)
        }.formStyle(.grouped).disabled(model.running)
    }

    private var ai: some View {
        Form {
            Section("OpenAI による競合解決") {
                Toggle("競合を自動解決する", isOn: $model.settings.autoResolve)
                SecureField("API key", text: $model.apiKey, prompt: Text("空欄で保存済みキーを保持"))
                    .textContentType(.password)
                TextField("モデル", text: $model.settings.model)
                Text("競合ファイルの共通祖先・ローカル版・リモート版を OpenAI API に送信します。API 料金が発生します。解決できない場合は停止します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("除外パス（部分一致・1 行に 1 件）") {
                TextEditor(text: $model.settings.excludedAIPaths)
                    .font(.system(.body, design: .monospaced)).frame(minHeight: 150)
                Text("この除外設定は差分表示にも使用します。暗号化ファイルは設定にかかわらず除外します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("設定を保存") { model.save() }.buttonStyle(.glassProminent)
        }.formStyle(.grouped).disabled(model.running)
    }

    private var diff: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mac ↔ 現在の source").font(.headline)
                Spacer()
                Button("差分を更新", systemImage: "arrow.clockwise") { model.start(.preview) }.disabled(model.running)
            }
            Text("リモートの取得前の差分です。除外パス・暗号化ファイルは表示しません。内容は保存せず、この画面だけで表示します。")
                .font(.caption).foregroundStyle(.secondary)
            if let preview = model.preview {
                Text("表示対象 \(preview.files.count) 件 · 除外 \(preview.omittedCount) 件\(preview.truncated ? " · 先頭 100,000 文字のみ" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                if preview.files.isEmpty {
                    ContentUnavailableView("表示対象の差分はありません", systemImage: "checkmark.circle")
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(preview.files.joined(separator: "\n")).foregroundStyle(.secondary)
                            Divider()
                            Text(preview.text.isEmpty ? "内容の差分はありません。" : preview.text)
                        }.font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }.background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))
                }
            } else {
                ContentUnavailableView("差分を確認", systemImage: "doc.text.magnifyingglass",
                                       description: Text("「差分を更新」で管理対象の変更を読み込みます。"))
            }
            if model.running { OperationStatus(model: model) }
        }.padding(24)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ファイル内容・API key は履歴に記録しません。直近 300 件を保存します。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(model.history.reversed().joined(separator: "\n\n"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("バックアップを開く", systemImage: "folder") { model.openBackups() }
        }.padding(24)
    }
}
