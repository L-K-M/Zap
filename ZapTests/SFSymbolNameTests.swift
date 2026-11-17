import AppKit
import XCTest
@testable import Zap

/// `Image(systemName:)` draws nothing at all for a symbol the system doesn't
/// know, so a bad name is a silent visual bug rather than a crash or a build
/// error. Minimized windows shipped without a glyph that way
/// (`macwindow.badge.minus` doesn't exist). These tests make a bad name fail.
final class SFSymbolNameTests: XCTestCase {

    func testWindowGlyphsResolve() {
        for name in WindowGlyph.allSymbolNames {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "SF Symbol '\(name)' does not exist")
        }
    }

    func testWindowGlyphDistinguishesMinimizedWindows() {
        XCTAssertEqual(WindowGlyph.symbolName(isMinimized: false), WindowGlyph.standard)
        XCTAssertEqual(WindowGlyph.symbolName(isMinimized: true), WindowGlyph.minimized)
        XCTAssertNotEqual(WindowGlyph.standard, WindowGlyph.minimized)
    }

    /// Every symbol name written as a literal next to `systemName:` or
    /// `systemSymbolName:` anywhere in the app's sources, ternaries included,
    /// must resolve on the system running the tests.
    func testEveryLiteralSymbolNameInTheAppResolves() throws {
        let names = try literalSymbolNames()
        // Guard the scan itself: a pattern that silently matched nothing would
        // make this test pass vacuously.
        XCTAssertGreaterThan(names.count, 5, "the source scan found too few symbol names")
        for name in names.sorted() {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "SF Symbol '\(name)' used in the app does not exist")
        }
    }

    // MARK: Source scan

    private func literalSymbolNames() throws -> Set<String> {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ZapTests
            .deletingLastPathComponent()      // repository root
            .appendingPathComponent("Zap", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("App sources not found at \(sources.path)")
        }

        let literal = try NSRegularExpression(pattern: #""([a-z0-9]+(?:\.[a-z0-9]+)*)""#)
        var names = Set<String>()
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n")
            where line.contains("systemName:") || line.contains("systemSymbolName:") {
                let line = String(line)
                let range = NSRange(line.startIndex..., in: line)
                for match in literal.matches(in: line, range: range) {
                    if let name = Range(match.range(at: 1), in: line) {
                        names.insert(String(line[name]))
                    }
                }
            }
        }
        return names
    }
}
