import Combine
import GoogleMobileAds
import os
import UIKit
import UserMessagingPlatform

/// AdMob の準備（広告の同意 → SDK の初期化）と、「いま広告を出してよいか」の窓口。
/// Android 版 `ads/AdsManager.kt` と同じ決めごと:
///
/// - **Pro は何もしない。** 同意フォームも SDK の初期化も広告リクエストも行わない。
///   起動時に Pro なら `prepare()` は何もせず、無料に戻ったとき（返金など）に初めて準備する。
///   無料 → Pro になった瞬間に `canShowAds` が false になり、画面側は広告を外して破棄する。
/// - **広告はおまけ。** 同意の確認・初期化・読み込みのどれが失敗しても、起動・再生・購入を待たせない
///   （すべて非同期で、終わったら `canShowAds` が変わるだけ）。
/// - 同意（UMP）は広告リクエストより先に確認する。EEA・英国・スイスなど同意が要る地域では
///   Google の同意フォームが出て、その結果で `canShowAds` が決まる。
/// - ATT（App Tracking Transparency）のダイアログは出さない。IDFA は使わない。
@MainActor
final class AdsManager: ObservableObject {

    let config: AdsConfig

    /// 広告を表示・リクエストしてよいか。画面はこれだけを見る。
    @Published private(set) var canShowAds = false
    /// 「広告のプライバシー設定」をアプリ内に出す必要があるか（同意が要る地域の無料版だけ true）。
    @Published private(set) var privacyOptionsRequired = false

    private var isPro: Bool
    private var canRequestByConsent = false
    private var isSDKReady = false
    private var requiresPrivacyOptions = false
    /// 同意の確認を始めたか（二重に始めない）。Pro では false のまま。
    private(set) var consentStarted = false
    private var sdkStarted = false
    /// 画面が出たか。同意フォームは画面の上に出すので、それまでは準備を始めない。
    private var isActivated = false
    private var cancellables = Set<AnyCancellable>()
    private let log = Logger(subsystem: "com.deskflowlabs.channeltimelineviewer", category: "Ads")

    init(config: AdsConfig = .current, isPro: Bool, isProPublisher: AnyPublisher<Bool, Never>) {
        self.config = config
        self.isPro = isPro
        isProPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pro in
                guard let self else { return }
                self.isPro = pro
                self.recompute()
                // Pro でなくなったとき（返金など）は、ここで初めて広告の準備をする。
                if !pro, self.isActivated { self.prepare() }
            }
            .store(in: &cancellables)
    }

    /// 最初の画面が出たときに呼ぶ（何度呼んでもよい）。Pro なら何もしない。
    func activate() {
        #if DEBUG
        // 起動引数 -NoAds YES で広告を出さない（ストア用スクリーンショットにテスト広告を写さないため）。
        if UserDefaults.standard.bool(forKey: "NoAds") { return }
        #endif
        isActivated = true
        prepare()
    }

    /// 広告の準備を始める。Pro でなくなったときにも呼ばれる（二重には始めない）。
    private func prepare() {
        guard AdVisibilityPolicy.shouldPrepare(isPro: isPro, isConfigured: config.isEnabled),
              !consentStarted else { return }
        consentStarted = true

        let parameters = RequestParameters()
        #if DEBUG
        // 起動引数 -AdsEEA YES で、EEA の同意フォームを試せる（シミュレーターのみ有効）。
        if UserDefaults.standard.bool(forKey: "AdsEEA") {
            let debugSettings = DebugSettings()
            debugSettings.geography = .EEA
            parameters.debugSettings = debugSettings
        }
        if UserDefaults.standard.bool(forKey: "AdsResetConsent") {
            ConsentInformation.shared.reset()
        }
        #endif

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    // 通信できない等。前回の同意で広告を出せるならそれを使う（出せないなら出さない）。
                    self.log.info("Consent info update failed: \(error.localizedDescription, privacy: .public)")
                    self.applyConsent()
                    return
                }
                ConsentForm.loadAndPresentIfRequired(from: Self.topViewController()) { [weak self] formError in
                    Task { @MainActor in
                        if let formError {
                            self?.log.info("Consent form: \(formError.localizedDescription, privacy: .public)")
                        }
                        self?.applyConsent()
                    }
                }
            }
        }
        // 前回までに同意が済んでいれば、今回の確認を待たずに準備を進めてよい（Google 推奨）。
        applyConsent()
    }

    /// 「広告のプライバシー設定」（同意の見直し）を開く。
    func showPrivacyOptions() {
        ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController()) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.log.info("Privacy options form: \(error.localizedDescription, privacy: .public)")
                }
                self?.applyConsent()
            }
        }
    }

    private func applyConsent() {
        requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        canRequestByConsent = ConsentInformation.shared.canRequestAds
        if canRequestByConsent { startSDKOnce() }
        recompute()
    }

    /// SDK の初期化は1回だけ。終わるまで広告は出さない（画面の表示は待たせない）。
    private func startSDKOnce() {
        guard !sdkStarted, !isPro else { return }
        sdkStarted = true
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor in
                self?.isSDKReady = true
                self?.recompute()
            }
        }
    }

    private func recompute() {
        canShowAds = AdVisibilityPolicy.canRequestAds(
            isPro: isPro, isConfigured: config.isEnabled,
            canRequestAds: canRequestByConsent, isSDKReady: isSDKReady)
        privacyOptionsRequired = !isPro && requiresPrivacyOptions
    }

    /// 画面（ウィンドウ）の幅。アンカー型バナーの大きさを決めるのに使う。
    static func windowWidth() -> CGFloat {
        let width = topViewController()?.view.window?.bounds.width ?? 0
        return width > 0 ? width : 375
    }

    /// 同意フォーム・広告のタップ先を出す画面（いちばん手前に出ている画面）。
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
