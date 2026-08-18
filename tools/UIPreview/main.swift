// アプリのパーツ（いまはリピートバッジ）を PNG に描き出すだけの小さなツール。
//
// 目的: 実機に入れる前に見た目を確認する。
//   Windows 環境では Xcode のプレビューが使えないため、GitHub Actions の macOS
//   ランナーで実アプリのソース（Views/RepeatModeBadge.swift）をそのままコンパイルし、
//   PNG を生成して成果物として持ち帰る。
//
// 実行: swiftc で本体のソースと一緒にビルドして起動する（.github/workflows/ui-preview.yml）。

import AppKit
import SwiftUI

/// 見比べる「上下の矢印の間隔」。線の太さは変えない。
let gaps: [CGFloat] = [0.0, 0.10, 0.16, 0.22]

func gapLabel(_ gap: CGFloat) -> String {
    switch gap {
    case 0.0: return "案1: いまのまま（間隔そのまま）"
    case 0.10: return "案2: 少し広げる"
    case 0.16: return "案3: もう少し広げる"
    default: return "案4: しっかり広げる"
    }
}

/// 3状態を、実寸と拡大で並べたシート。
struct RepeatBadgeSheet: View {
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(dark ? "ダークモード" : "ライトモード")
                .font(.headline)
            ForEach(gaps, id: \.self) { gap in
                VStack(alignment: .leading, spacing: 6) {
                    Text(gapLabel(gap)).font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 28) {
                        ForEach(RepeatMode.allCases) { mode in
                            VStack(spacing: 10) {
                                // ツールバーでの実寸
                                RepeatModeBadge(mode: mode, arrowGap: gap)
                                // 形が分かるように拡大
                                RepeatModeBadge(mode: mode, size: 88, arrowGap: gap)
                                Text(mode.label).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .padding(28)
        .background(dark ? Color.black : Color.white)
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

@MainActor
func writePNG<V: View>(_ view: V, to url: URL, scale: CGFloat = 3) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("描き出しに失敗: \(url.lastPathComponent)\n".utf8))
        return
    }
    try? png.write(to: url)
    print("wrote \(url.path)")
}

MainActor.assumeIsolated {
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
                              ? CommandLine.arguments[1]
                              : "./build/ui-preview")
    try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    writePNG(RepeatBadgeSheet(dark: false),
             to: outputDirectory.appendingPathComponent("repeat-badge-light.png"))
    writePNG(RepeatBadgeSheet(dark: true),
             to: outputDirectory.appendingPathComponent("repeat-badge-dark.png"))
}
