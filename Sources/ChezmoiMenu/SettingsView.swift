import SwiftUI
import ChezmoiCore

private enum DiffMode: String, CaseIterable, Identifiable {
    case uncommitted = "未コミット"
    case upstream = "コミット済み ↔ upstream"
    case destination = "Mac ↔ source"
    var id: Self { self }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var diffMode = DiffMode.uncommitted
    @State private var commitMessage = "Update dotfiles"
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
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                             ?? "開発ビルド").font(.caption2).foregroundStyle(.secondary)
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
            .sheet(item: Binding(get: { model.conflictSelection }, set: { value in
                if value == nil && model.conflictSelection != nil { model.cancel() }
            })) { request in
                ConflictSelectionView(request: request, onSelect: {
                    model.selectConflictVersions($0, requestID: request.id)
                }, onCancel: { model.cancel() })
            }
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
                Text("この除外設定は差分の内容表示にも使用します。暗号化ファイルの内容は設定にかかわらず非表示です。通常の同期には含まれます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("設定を保存") { model.save() }.buttonStyle(.glassProminent)
        }.formStyle(.grouped).disabled(model.running)
    }

    private var diff: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("変更とコミット").font(.headline)
                Spacer()
                Button("差分を更新", systemImage: "arrow.clockwise") { refreshDiff() }.disabled(model.running)
            }
            Picker("比較対象", selection: $diffMode) {
                ForEach(DiffMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).disabled(model.running)
            Text(diffDescription).font(.caption).foregroundStyle(.secondary)
            Text("暗号化ファイル・除外パスは名前のみ表示します。通常の同期・コミットには含まれます。")
                .font(.caption).foregroundStyle(.secondary)
            if diffMode == .uncommitted {
                HStack {
                    TextField("コミットメッセージ", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                    Button("source をコミット", systemImage: "checkmark.circle") {
                        model.start(.commitSource(commitMessage))
                    }.buttonStyle(.glassProminent)
                        .disabled(model.running || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || currentDiff.map { $0.files.isEmpty && $0.omittedFiles.isEmpty } != false)
                }.disabled(model.running)
            }
            if diffMode == .upstream, let source = model.sourcePreview {
                Text(source.upstream == nil ? "upstream が未設定です。" : "upstream より \(source.ahead) コミット先行 · \(source.behind) コミット遅延")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let preview = currentDiff {
                Text("内容表示 \(preview.files.count) 件 · 内容非表示 \(preview.omittedCount) 件\(preview.truncated ? " · 先頭 100,000 文字のみ" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                if preview.files.isEmpty && preview.omittedFiles.isEmpty {
                    ContentUnavailableView("差分はありません", systemImage: "checkmark.circle")
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 18) {
                            if !preview.files.isEmpty {
                                Text(preview.files.joined(separator: "\n")).foregroundStyle(.secondary)
                                Divider()
                                Text(preview.text.isEmpty ? "内容の差分はありません。" : preview.text)
                            }
                            if !preview.omittedFiles.isEmpty {
                                Label("内容を表示しない変更", systemImage: "lock.doc")
                                    .font(.headline)
                                Text("暗号化ファイルまたは除外パスのため、内容を非表示にしています。通常ファイルの競合時は、ローカルかリモートの版を選択できます。")
                                    .font(.callout).foregroundStyle(.secondary)
                                Text(preview.omittedFiles.joined(separator: "\n"))
                            }
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
            .task {
                if model.sourcePreview == nil && !model.running { refreshDiff() }
            }
            .onChange(of: diffMode) { if !model.running { refreshDiff() } }
            .onChange(of: model.lastSourceCommit) { diffMode = .upstream }
    }

    private var currentDiff: DiffPreview? {
        switch diffMode {
        case .uncommitted: model.sourcePreview?.uncommitted
        case .upstream: model.sourcePreview?.upstream
        case .destination: model.preview
        }
    }

    private var diffDescription: String {
        switch diffMode {
        case .uncommitted: "source と直前のコミットを比較します。ステージ済み・未ステージ・新規ファイルを含む source の変更をすべてコミットします。"
        case .upstream: "取得済みの upstream と現在のコミットを比較します。リモートの最新状態は同期時に取得します。送信する場合は Upload を実行してください。"
        case .destination: "Mac と現在の source を比較します。source に反映済みの未コミット変更は、この比較には表示されません。"
        }
    }

    private func refreshDiff() {
        model.start(diffMode == .destination ? .preview : .sourcePreview)
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
