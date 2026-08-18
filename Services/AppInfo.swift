import Foundation

/// アプリ本体の表示名を返すだけの小さなヘルパー。
///
/// 画面の説明文には「共有シートで『Channel Timeline Viewer』を選ぶ」のように
/// アプリ名が何度も出てくる。翻訳文の中に製品名を埋め込むと言語ごとに書き換えが必要になるため、
/// 文言側は `%@` にしておき、ここで得た名前を差し込む。
enum AppInfo {
    /// 製品名（App Store の表示名）。翻訳しない。
    static let productName = "Channel Timeline Viewer"

    /// 本体アプリの表示名。
    ///
    /// 共有シート等の App Extension から見た `Bundle.main` は**拡張自身**のバンドルで、
    /// そこには拡張の名前（例:「Channel Timelineで開く」）が入っている。
    /// 拡張から呼ばれたときは本体の名前を出したいので、その場合は `productName` を返す。
    static var displayName: String {
        guard Bundle.main.bundleURL.pathExtension != "appex" else { return productName }
        return (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? productName
    }
}
