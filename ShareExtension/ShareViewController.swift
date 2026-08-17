import UIKit
import UniformTypeIdentifiers
import UserNotifications

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
    private let allowButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    /// 受け取った YouTube URL（通知を許可したあとに使う）。
    private var pendingLink: String?

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

        // iOS では、共有シート拡張からアプリを直接開くことは許可されていない
        // （`NSExtensionContext.open` が使えるのは Today / iMessage 拡張のみ）。
        // 環境によっては通る場合があるので一応試し、駄目なら
        //   1) 通知を許可済み → ローカル通知（タップでアプリが開く）
        //   2) 未許可 → クリップボード経由（アプリを開くと「共有されたURLを開く」が出る）
        // の順にフォールバックする。どちらの場合もクリップボードには入れておく。
        UIPasteboard.general.string = link
        pendingLink = link
        statusLabel.text = "Channel Timeline Viewer に受け渡しています…"

        if await open(appURL) {
            complete()
            return
        }

        if await postNotification(for: link) {
            // 通知バナーがすぐ出るので、共有シートは閉じてしまう方が分かりやすい。
            complete()
            return
        }

        // まだ通知を許可していない場合は、ここで許可すればワンタップで開けるようになる。
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .notDetermined {
            showAuthorizationOffer()
        } else {
            showHandoff("URL を受け取りました。\nChannel Timeline Viewer を開くと、"
                        + "「共有されたURLを開く」からこのチャンネルを表示できます。")
        }
    }

    /// 「通知を許可すると、ここからそのまま開けます」の案内を出す。
    private func showAuthorizationOffer() {
        indicator.stopAnimating()
        statusLabel.text = "URL を受け取りました。\n"
            + "通知を許可すると、この直後に出る通知をタップするだけで開けます。\n"
            + "（許可しない場合は、アプリを開いて「共有されたURLを開く」から表示できます）"
        allowButton.isHidden = false
        closeButton.isHidden = false
    }

    /// 通知を許可 → その場で通知を出す。通知をタップするとアプリが開く。
    @objc private func allowTapped() {
        allowButton.isEnabled = false
        indicator.startAnimating()
        statusLabel.text = "通知を準備しています…"
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert])) ?? false
            if granted, let link = pendingLink, await postNotification(for: link) {
                complete()
            } else {
                allowButton.isHidden = true
                showHandoff("URL を受け取りました。\nChannel Timeline Viewer を開くと、"
                            + "「共有されたURLを開く」からこのチャンネルを表示できます。")
            }
        }
    }

    /// 通知を許可済みなら、タップでアプリを開けるローカル通知を出す。
    /// 未許可のときは**許可を求めず**（拡張から尋ねない）、false を返す。
    private func postNotification(for link: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        guard authorized, let request = SharedLinkNotifier.makeRequest(for: link) else {
            return false
        }
        do {
            try await center.add(request)
            return true
        } catch {
            return false
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

    /// 失敗ではなく「受け渡し完了」の案内（アプリを開けば続きができる）。
    private func showHandoff(_ message: String) {
        indicator.stopAnimating()
        statusLabel.text = message
        allowButton.isHidden = true
        closeButton.setTitle("閉じる", for: .normal)
        closeButton.isHidden = false
    }

    private func showFailure(_ message: String) {
        indicator.stopAnimating()
        statusLabel.text = message
        allowButton.isHidden = true
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

        allowButton.setTitle("通知を許可して開く", for: .normal)
        allowButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        allowButton.addTarget(self, action: #selector(allowTapped), for: .touchUpInside)
        allowButton.isHidden = true

        closeButton.setTitle("閉じる", for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.isHidden = true

        indicator.startAnimating()

        let stack = UIStackView(
            arrangedSubviews: [titleLabel, indicator, statusLabel, allowButton, closeButton])
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
