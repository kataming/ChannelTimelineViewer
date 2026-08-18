// アプリのパーツ（いまはリピートバッジ）を PNG に描き出すツール。
//
// 目的:
//  1) 実機に入れる前に見た目を確認する（Windows では Xcode プレビューが使えないため）
//  2) 目標の見た目に合う数値（線の太さ・大きさ・間隔）を総当たりで探す
//
// 実行: .github/workflows/ui-preview.yml から。

import AppKit
import SwiftUI

// MARK: - 仕上がり確認用のシート

struct RepeatBadgeSheet: View {
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(dark ? "ダークモード" : "ライトモード").font(.headline)
            HStack(alignment: .top, spacing: 28) {
                ForEach(RepeatMode.allCases) { mode in
                    VStack(spacing: 10) {
                        RepeatModeBadge(mode: mode)               // 実寸
                        RepeatModeBadge(mode: mode, size: 88)     // 拡大
                        Text(mode.label).font(.caption)
                    }
                }
            }
        }
        .padding(28)
        .background(dark ? Color.black : Color.white)
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

// MARK: - 数値合わせ用（1個ずつ書き出して計測する）

struct SingleBadge: View {
    let gap: CGFloat
    let glyphRatio: CGFloat
    let weight: Font.Weight
    let labelRatio: CGFloat

    var body: some View {
        RepeatModeBadge(mode: .all, size: 220,
                        arrowGap: gap,
                        glyphRatio: glyphRatio,
                        glyphWeight: weight,
                        labelRatio: labelRatio)
            .padding(20)
            .background(Color.white)
    }
}

let weights: [(String, Font.Weight)] = [
    ("ultraLight", .ultraLight), ("thin", .thin), ("light", .light), ("regular", .regular),
]
let glyphRatios: [CGFloat] = [0.52, 0.60, 0.68]
let gaps: [CGFloat] = [0.10, 0.16, 0.22]

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
}

MainActor.assumeIsolated {
    let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
                  ? CommandLine.arguments[1] : "./build/ui-preview")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    writePNG(RepeatBadgeSheet(dark: false), to: out.appendingPathComponent("repeat-badge-light.png"))
    writePNG(RepeatBadgeSheet(dark: true), to: out.appendingPathComponent("repeat-badge-dark.png"))

    // 数値合わせ用（計測してから消す）
    let matrix = out.appendingPathComponent("matrix", isDirectory: true)
    try? FileManager.default.createDirectory(at: matrix, withIntermediateDirectories: true)
    for (wname, weight) in weights {
        for glyph in glyphRatios {
            for gap in gaps {
                let name = "w-\(wname)_glyph-\(Int(glyph * 100))_gap-\(Int(gap * 100)).png"
                writePNG(SingleBadge(gap: gap, glyphRatio: glyph, weight: weight, labelRatio: 0.26),
                         to: matrix.appendingPathComponent(name), scale: 1)
            }
        }
    }
    print("done")
}
