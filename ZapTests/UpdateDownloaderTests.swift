import XCTest
@testable import Zap

final class UpdateDownloaderTests: XCTestCase {

    func testUniqueDestinationAvoidsCollisions() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UpdateDownloaderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let first = UpdateDownloader.uniqueDestination(in: dir, fileName: "Zap.dmg", fileManager: fm)
        XCTAssertEqual(first.lastPathComponent, "Zap.dmg")
        XCTAssertTrue(fm.createFile(atPath: first.path, contents: Data()))

        let second = UpdateDownloader.uniqueDestination(in: dir, fileName: "Zap.dmg", fileManager: fm)
        XCTAssertEqual(second.lastPathComponent, "Zap-1.dmg")
        XCTAssertTrue(fm.createFile(atPath: second.path, contents: Data()))

        let third = UpdateDownloader.uniqueDestination(in: dir, fileName: "Zap.dmg", fileManager: fm)
        XCTAssertEqual(third.lastPathComponent, "Zap-2.dmg")
    }

    func testUniqueDestinationHandlesNameWithoutExtension() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UpdateDownloaderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let first = UpdateDownloader.uniqueDestination(in: dir, fileName: "Zap", fileManager: fm)
        XCTAssertEqual(first.lastPathComponent, "Zap")
        XCTAssertTrue(fm.createFile(atPath: first.path, contents: Data()))

        let second = UpdateDownloader.uniqueDestination(in: dir, fileName: "Zap", fileManager: fm)
        XCTAssertEqual(second.lastPathComponent, "Zap-1")
    }
}
