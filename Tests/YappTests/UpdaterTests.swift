import XCTest
import Sparkle
@testable import yapp

final class UpdaterTests: XCTestCase {
    @MainActor
    func testBackgroundAndProbeChecksAreRejected() throws {
        let delegate = AppUpdater()
        let updater = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil
        ).updater
        XCTAssertThrowsError(try delegate.updater(updater, mayPerform: .updatesInBackground))
        XCTAssertThrowsError(try delegate.updater(updater, mayPerform: .updateInformation))
        XCTAssertNoThrow(try delegate.updater(updater, mayPerform: .updates))
    }

    func testDistributionConfigurationRequiresManualSignedHTTPSUpdates() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["SUFeedURL"] as? String, "https://yapp.now/appcast.xml")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(plist["SUPublicEDKey"] as? String))?.count, 32)
        for key in ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling"] {
            XCTAssertEqual(plist[key] as? Bool, false, key)
        }
        XCTAssertEqual(plist["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
    }
}
