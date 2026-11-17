import ScreenCaptureKit
import XCTest
@testable import Zap

final class ThumbnailContentFetchTests: XCTestCase {
    func testConcurrentCapturesShareAWindowListFetch() async throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Requires ScreenCaptureKit capture") }
        let loader = Loader()
        let provider = WindowThumbnailProvider(fetchContent: { await loader.fetch() })

        await withTaskGroup(of: Void.self) { group in
            for windowID in 1...3 {
                group.addTask { _ = await provider.thumbnail(for: CGWindowID(windowID), maxDimension: 160) }
            }
        }

        let count = await loader.requests
        XCTAssertEqual(count, 1)
    }

    func testClearingAbandonsThePreviousWindowListFetch() async throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Requires ScreenCaptureKit capture") }
        let loader = Loader()
        let provider = WindowThumbnailProvider(fetchContent: { await loader.fetch() })

        async let old = provider.thumbnail(for: 1, maxDimension: 160)
        await loader.waitUntilStarted()
        await provider.clear()
        _ = await provider.thumbnail(for: 2, maxDimension: 160)
        _ = await old

        let count = await loader.requests
        XCTAssertEqual(count, 2)
    }

    private actor Loader {
        private(set) var requests = 0
        private var started: CheckedContinuation<Void, Never>?

        func waitUntilStarted() async {
            guard requests == 0 else { return }
            await withCheckedContinuation { started = $0 }
        }

        func fetch() async -> SCShareableContent? {
            requests += 1
            started?.resume()
            started = nil
            // Simulate suspended system enumeration without requesting screen access.
            try? await Task.sleep(nanoseconds: 150_000_000)
            return nil
        }
    }
}
