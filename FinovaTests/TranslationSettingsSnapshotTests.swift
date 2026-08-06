//
//  TranslationSettingsSnapshotTests.swift
//  FinovaTests
//
//  Renders the tag-translation rows in every state they can be in, so the layout can be reviewed
//  without signing in — and so the states that only occur mid-download, or on a device that cannot
//  translate at all, can be looked at without engineering the conditions on a real phone.
//
//  Set FINOVA_SNAPSHOT_DIR to collect the PNGs; the XCTAttachments are always produced.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

@MainActor
final class TranslationSettingsSnapshotTests: XCTestCase {

    private let rowWidth: CGFloat = 393

    /// Renders just the translation group, cropped to its own height — the surrounding Settings
    /// screen needs a signed-in view model and is not what is under review here.
    private func render(_ name: String, configure: (SettingsView) -> Void) {
        let view = SettingsView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: rowWidth, height: 900))
        window.backgroundColor = Colors.gray200
        window.isHidden = false
        window.makeKeyAndVisible()
        view.frame = window.bounds
        window.addSubview(view)

        configure(view)

        window.setNeedsLayout()
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        guard let group = view.translationGroupFrame else {
            XCTFail("\(name): the translation rows are not in the hierarchy")
            return
        }
        let bounds = view.convert(group, to: window)
        let size = CGSize(width: rowWidth, height: max(bounds.height + 24, 1))
        let image = UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.translateBy(x: 0, y: -bounds.minY + 12)
            window.layer.render(in: context.cgContext)
        }

        guard let data = image.pngData() else {
            XCTFail("could not encode \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["FINOVA_SNAPSHOT_DIR"] else {
            print("SNAPSHOT_ATTACHED \(name) (\(data.count) bytes); set FINOVA_SNAPSHOT_DIR to save")
            return
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("translation-\(name).png")
        do {
            try data.write(to: url)
            print("SNAPSHOT_WRITTEN \(name) -> \(url.path) (\(data.count) bytes)")
        } catch {
            XCTFail("could not write \(name): \(error)")
        }
    }

    // MARK: - States

    func testRenderTranslationOff() {
        render("off") { view in
            view.setTranslationGroupHidden(false)
            view.translateTagsSwitch.isOn = false
            view.applyDownloadState(.hidden)
            view.setTranslationFooter("settings.translateTags.footer".localized)
        }
    }

    func testRenderTranslationOnNothingToDo() {
        render("on-idle") { view in
            view.setTranslationGroupHidden(false)
            view.translateTagsSwitch.isOn = true
            view.applyDownloadState(.hidden)
            view.setTranslationFooter("settings.translateTags.footer".localized)
        }
    }

    func testRenderDownloadAvailable() {
        render("download-available") { view in
            view.setTranslationGroupHidden(false)
            view.translateTagsSwitch.isOn = true
            view.applyDownloadState(.available(languageName: "Português (Brasil)"))
            view.setTranslationFooter(
                "settings.translateTags.footer".localized + "\n"
                    + String(
                        format: "settings.translateTags.download.footer".localized,
                        "Português (Brasil)"))
        }
    }

    func testRenderDownloading() {
        render("downloading") { view in
            view.setTranslationGroupHidden(false)
            view.translateTagsSwitch.isOn = true
            view.applyDownloadState(.downloading)
            view.setTranslationFooter("settings.translateTags.footer.downloading".localized)
        }
    }

    func testRenderDownloaded() {
        render("downloaded") { view in
            view.setTranslationGroupHidden(false)
            view.translateTagsSwitch.isOn = true
            view.applyDownloadState(.downloaded)
            view.setTranslationFooter("settings.translateTags.footer.downloaded".localized)
        }
    }

    func testRenderStalled() {
        render("stalled") { view in
            view.setTranslationGroupHidden(false)
            view.translateTagsSwitch.isOn = true
            view.applyDownloadState(.stalled)
            view.setTranslationFooter("settings.translateTags.footer.failed".localized)
        }
    }

    // MARK: - Behaviour the renders depend on

    func testTheDownloadRowIsOneAccessibilityElementAndDescribesItsState() {
        let view = SettingsView()
        view.applyDownloadState(.available(languageName: "Português (Brasil)"))

        let row = view.downloadLanguagesContainer
        XCTAssertTrue(row.isAccessibilityElement, "else the chevron announces as an unlabelled image")
        XCTAssertEqual(
            row.accessibilityLabel,
            "settings.translateTags.download.title".localized + ", Português (Brasil)")
        XCTAssertEqual(row.accessibilityTraits, .button)
        XCTAssertNotNil(row.accessibilityHint)
    }

    func testTheDoneStateIsNotTappable() {
        let view = SettingsView()
        view.applyDownloadState(.downloaded)

        XCTAssertFalse(view.downloadLanguagesContainer.isUserInteractionEnabled)
        XCTAssertTrue(view.downloadLanguagesContainer.accessibilityTraits.contains(.notEnabled))
    }

    func testTheDownloadingStateStaysTappable() {
        // Re-tapping is harmless and is the only way back if the user dismissed the system sheet
        // before confirming, so this row must never disable itself.
        let view = SettingsView()
        view.applyDownloadState(.downloading)

        XCTAssertTrue(view.downloadLanguagesContainer.isUserInteractionEnabled)
    }

    func testHidingTheGroupHidesEveryPartOfIt() {
        let view = SettingsView()
        view.applyDownloadState(.available(languageName: "Português (Brasil)"))
        view.setTranslationFooter("something")

        view.setTranslationGroupHidden(true)

        XCTAssertTrue(view.translateTagsContainer.isHidden)
        XCTAssertTrue(view.downloadLanguagesContainer.isHidden)
    }
}
