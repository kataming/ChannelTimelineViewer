import SwiftUI

/// 再生設定（速度・字幕）を**プレイヤーの外**で操作するシート。
///
/// 公式プレイヤーの設定メニューは iframe の内部に描画されるため、
/// 16:9 の枠に埋め込んでいる本アプリでは下が切れて操作できない。
/// そこで同じ操作を公式 IFrame Player API 経由でアプリ側の画面から行えるようにしている
/// （プレイヤーの見た目や再生そのものには手を加えない）。
struct PlaybackOptionsSheet: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("再生速度") {
                    ForEach(viewModel.availableRates, id: \.self) { rate in
                        Button {
                            viewModel.setPlaybackRate(rate)
                        } label: {
                            HStack {
                                Text(PlayerViewModel.rateLabel(rate))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isCurrentRate(rate) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        viewModel.setCaptionTrack(nil)
                    } label: {
                        HStack {
                            Text("オフ").foregroundStyle(.primary)
                            Spacer()
                            if viewModel.options.activeCaption == nil {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }

                    ForEach(viewModel.options.captions) { track in
                        Button {
                            viewModel.setCaptionTrack(track.code)
                        } label: {
                            HStack {
                                Text(track.name).foregroundStyle(.primary)
                                Spacer()
                                if viewModel.options.activeCaption == track.code {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("字幕")
                } footer: {
                    if viewModel.options.captions.isEmpty {
                        Text("この動画で使える字幕はまだ読み込まれていません。"
                             + "再生を始めてからもう一度開くと表示されます（字幕が無い動画もあります）。")
                    } else {
                        Text("字幕は既定でオフから始まります。")
                    }
                }

                Section {
                    LabeledContent("画質", value: "自動")
                } footer: {
                    Text("画質は YouTube 側が通信状況に合わせて自動で調整します"
                         + "（公式プレイヤーの仕様上、アプリからは指定できません）。\n"
                         + "自分で選ぶ場合は、再生を始めてから "
                         + "プレイヤー右下の全画面ボタン → 歯車 → 画質 で変更できます"
                         + "（再生前に開くと画質の項目は出ません）。")
                }
            }
            .navigationTitle("再生設定")
            .navigationBarTitleDisplayMode(.inline)
            // 字幕トラックは再生開始から少し遅れて用意されるので、開くたびに取り直す。
            .task { viewModel.refreshOptions() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 端数の丸め誤差を避けて現在の速度と比べる。
    private func isCurrentRate(_ rate: Double) -> Bool {
        abs(viewModel.options.rate - rate) < 0.001
    }
}
