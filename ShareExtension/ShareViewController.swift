import UIKit
import UniformTypeIdentifiers

/// 共有シート（YouTube アプリ / Safari など）から YouTube の URL を受け取り、
/// メインアプリ（Channel Timeline Viewer）をカスタム URL で開くだけの Share Extension。
///
/// 方針（審査・保守の都合で意図的に最小限）:
/// - **YouTube Data API は呼ばない**（API キーの管理・エラー処理はメインアプリに集約）
/// - **スクレイピング・ダウンロード・再生は一切しない**（URL を受け渡すだけ）
/// - 受け取れるのは `public.url` と `public.plain-text`。YouTube アプリが URL ではなく
///   「タイトル + URL」のテキストとして共有してくる場合にも対応する。
final class ShareViewController: UIViewController {

    private let card = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let closeButton = UIButton(type: .system)

    // MARK: - ライフサイクル

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await process() }
    }

    // MARK: - 共有内容の処理

    private func process() async {
        guard let link = await extractYouTubeLink() else {
            showFailure("YouTube の URL が見つかりませんでした。\n動画またはチャンネルのページから共有してください。")
            return
        }
        guard let appURL = SharedLinkParser.makeAppURL(for: link) else {
            showFailure("この URL は開けませんでした。")
            return
        }

        statusLabel.text = "Channel Timeline Viewer を開いています…"
        let opened = await open(appURL)
        if opened {
            complete()
        } else {
            // まれに拡張機能からのアプリ起動が許可されないことがある。
            // その場合でも手作業に戻れるよう、URL をコピーして案内する。
            UIPasteboard.general.string = link
            showFailure("アプリを自動で開けませんでした。\nURL をコピーしたので、Channel Timeline Viewer を開いて貼り付けてください。")
        }
    }

    /// 共有されたアイテムから最初の YouTube URL を取り出す。
    private func extractYouTubeLink() async -> String? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                // 1) URL として共有された場合
                if let url = await loadURL(from: provider),
                   let link = SharedLinkParser.normalizedYouTubeURLString(url.absoluteString) {
                    return link
                }
                // 2) テキストとして共有された場合（YouTube アプリはこちらのことがある）
                if let text = await loadText(from: provider),
                   let link = SharedLinkParser.extractYouTubeURLString(from: text) {
                    return link
                }
            }
            // 3) 添付ではなく attributedContentText に入っている場合
            if let text = item.attributedContentText?.string,
               let link = SharedLinkParser.extractYouTubeURLString(from: text) {
                return link
            }
        }
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        let type = UTType.url.identifier
        guard provider.hasItemConformingToTypeIdentifier(type) else { return nil }
        let value = await loadItem(from: provider, typeIdentifier: type)
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        if let data = value as? Data, let string = String(data: data, encoding: .utf8) {
            return URL(string: string)
        }
        return nil
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        for type in [UTType.plainText.identifier, UTType.text.identifier] {
            guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
            let value = await loadItem(from: provider, typeIdentifier: type)
            if let string = value as? String { return string }
            if let url = value as? URL { return url.absoluteString }
            if let data = value as? Data, let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return nil
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async -> Any? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }

    // MARK: - メインアプリを開く / 終了

    /// Extension からメインアプリを開く（`NSExtensionContext.open`）。
    private func open(_ url: URL) async -> Bool {
        guard let context = extensionContext else { return false }
        return await withCheckedContinuation { continuation in
            context.open(url) { success in
                continuation.resume(returning: success)
            }
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func showFailure(_ message: String) {
        indicator.stopAnimating()
        statusLabel.text = message
        closeButton.isHidden = false
    }

    @objc private func closeTapped() {
        complete()
    }

    // MARK: - UI（最小限のシート表示）

    private func setUpUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)

        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 16
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        titleLabel.text = "Channel Timeline Viewer"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        statusLabel.text = "共有された URL を読み取っています…"
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        closeButton.setTitle("閉じる", for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.isHidden = true

        indicator.startAnimating()

        let stack = UIStackView(arrangedSubviews: [titleLabel, indicator, statusLabel, closeButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 340),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
        ])
    }
}
