import UIKit
import XCTest
@testable import ChannelTimelineViewer

/// 案内の画像（7言語）を、アプリの表示言語に合わせて選ぶ。
final class TutorialImageLanguageTests: XCTestCase {

    func testSevenLanguagesMapToTheirImages() {
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "ja"), "ja")
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "en"), "en")
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "zh-Hans"), "zh_Hans")
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "es"), "es")
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "de"), "de")
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "fr"), "fr")
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "ko"), "ko")
    }

    /// 繁体字には簡体字の画像を見せない。画像の無い言語は英語。
    func testOtherLanguagesFallBackToEnglish() {
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "zh-Hant"), "en")
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "pt-BR"), "en")
        XCTAssertEqual(TutorialImageLanguage.imageLanguage(forLocalization: "th"), "en")
    }

    /// 4枚の絵が7言語すべてアプリに入っている。
    func testAllGuideImagesAreBundled() {
        for language in TutorialImageLanguage.available {
            for number in 1...4 {
                XCTAssertNotNil(UIImage(named: "copyguide_ios_frame\(number)_\(language)"),
                                "copyguide_ios_frame\(number)_\(language) が無い")
            }
        }
    }
}
