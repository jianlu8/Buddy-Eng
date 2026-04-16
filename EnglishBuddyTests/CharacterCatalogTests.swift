import XCTest
@testable import EnglishBuddyCore

final class CharacterCatalogTests: XCTestCase {
    func testFlagshipBundleUsesPhotoPseudo3DMainPath() {
        let bundle = CharacterCatalog.bundle(for: CharacterCatalog.flagship.id)

        XCTAssertEqual(bundle.renderRuntimeKind, .photoPseudo3D)
        XCTAssertEqual(bundle.portraitProfileID, CharacterCatalog.primaryPortraitProfile.id)
        XCTAssertTrue(bundle.isReleaseReady)
    }

    func testLegacyBundlesRemainFallbackOnly() {
        let legacyIDs = ["lyra", "sol"]

        for characterID in legacyIDs {
            let bundle = CharacterCatalog.bundle(for: characterID)
            XCTAssertEqual(bundle.renderRuntimeKind, .legacyFallback)
            XCTAssertFalse(bundle.isReleaseReady)
        }
    }

    func testSelectableProfilesReflectPortraitAvailability() {
        let selectableIDs = CharacterCatalog.selectableProfiles.map(\.id)

        if CharacterCatalog.primaryPortraitAvailable {
            XCTAssertEqual(selectableIDs, [CharacterCatalog.flagship.id])
        } else {
            XCTAssertTrue(selectableIDs.contains(CharacterCatalog.flagship.id))
            XCTAssertTrue(selectableIDs.contains("lyra"))
            XCTAssertTrue(selectableIDs.contains("sol"))
        }
    }

    func testVisibleVoiceBundlesStayFemaleOnlyForCurrentFlagshipRelease() {
        let visibleIDs = VoiceCatalog.bundles(
            for: CharacterCatalog.flagship.id,
            languageID: LanguageCatalog.english.id
        ).map(\.id)

        XCTAssertEqual(visibleIDs, ["nova-voice", "lyra-voice"])
    }

    func testHiddenMaleVoiceBundlesRemainResolvableForFutureRolePackages() {
        let bundle = VoiceCatalog.bundle(
            for: "michael-voice",
            characterID: CharacterCatalog.flagship.id,
            languageID: LanguageCatalog.english.id
        )

        XCTAssertEqual(bundle.id, "michael-voice")
        XCTAssertEqual(bundle.genderPresentation, .male)
        XCTAssertFalse(bundle.isUserVisible)
        XCTAssertEqual(bundle.ttsModelFamily, .kokoro)
    }
}
