import XCTest
@testable import EnglishBuddyCore

final class AppFilesystemTests: XCTestCase {
    func testPrepareDirectoriesCreatesSplitStorePaths() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filesystem = AppFilesystem(baseURL: baseURL)

        try filesystem.prepareDirectories()

        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.userDataDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.modelStateDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.assetStateDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.migrationsDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.validationDirectoryURL.path))
    }
}
