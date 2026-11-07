import SwiftUI
import ChezmoiCore

struct ConflictSelectionView: View {
    let request: ConflictSelectionRequest
    let onSelect: ([String: ConflictSide]) -> Void
    let onCancel: () -> Void
    @State private var choices: [String: ConflictSide] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("競合ファイルで採用する版を選択").font(.title2.bold())
            Text("選択した版でファイル全体を置き換えます。両方の版はバックアップと Git 履歴に残ります。内容は表示せず、AI にも送信しません。")
                .foregroundStyle(.secondary)
            Text("ローカル: \(request.localHead.prefix(8)) · リモート: \(request.remoteHead.prefix(8))")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            HStack {
                Button("すべてローカル") { chooseAll(.local) }
                Button("すべてリモート") { chooseAll(.remote) }
                Spacer()
                Text("選択済み \(choices.count) / \(request.conflicts.count) 件")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(request.conflicts, id: \.path) { conflict in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(conflict.path).font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                            Picker("採用する版", selection: Binding<ConflictSide?>(
                                get: { choices[conflict.path] },
                                set: { choices[conflict.path] = $0 })) {
                                Text("選択してください").tag(Optional<ConflictSide>.none)
                                Text(conflict.localDeleted ? "ローカルを採用（管理対象から削除）" : "ローカルを採用")
                                    .tag(Optional(ConflictSide.local))
                                Text(conflict.remoteDeleted ? "リモートを採用（管理対象から削除）" : "リモートを採用")
                                    .tag(Optional(ConflictSide.remote))
                            }.pickerStyle(.menu)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }.padding(12)
            }.background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))
            if request.conflicts.contains(where: { $0.localDeleted || $0.remoteDeleted }) {
                Text("削除された版を選ぶと source の管理対象から外れます。ホーム側に配置済みのファイルは残ります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(request.direction == .upload
                 ? "選択後に統合・適用し、リモートへ送信します。競合していない変更は通常どおり統合します。"
                 : "選択後に統合し、この Mac に適用します。リモートへの送信は行いません。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("同期を中止", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("選択した版で同期を続ける") { onSelect(choices) }
                    .buttonStyle(.glassProminent)
                    .disabled(choices.count != request.conflicts.count)
            }
        }.padding(24).frame(minWidth: 640, idealWidth: 720, minHeight: 460, idealHeight: 560)
            .interactiveDismissDisabled()
    }

    private func chooseAll(_ side: ConflictSide) {
        choices = Dictionary(uniqueKeysWithValues: request.conflicts.map { ($0.path, side) })
    }
}
