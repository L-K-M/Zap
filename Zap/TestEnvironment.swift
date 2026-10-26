import Foundation

/// Whether the process is running under XCTest, for the few global hooks that
/// must not install in tests (status item, event tap, update checks).
enum TestEnvironment {

    /// Two signals because either can be the one present: the test bundle's
    /// classes loaded (`XCTestCase` exists), or the runner injected its
    /// configuration path.
    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
