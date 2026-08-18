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
                Section("options.rate.section") {
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
                            Text("captions.off").foregroundStyle(.primary)
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
                    Text("options.captions.section")
                } footer: {
                    if viewModel.options.captions.isEmpty {
                        Text("options.captions.notLoaded")
                    } else {
                        Text("options.captions.defaultOff")
                    }
                }

                Section {
                    LabeledContent(String(localized: "options.quality.title"),
                                   value: String(localized: "options.quality.auto"))
                } footer: {
                    Text("options.quality.note")
                }
            }
            .navigationTitle(Text("options.title"))
            .navigationBarTitleDisplayMode(.inline)
            // 字幕トラックは再生開始から少し遅れて用意されるので、開くたびに取り直す。
            .task { viewModel.refreshOptions() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }
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
