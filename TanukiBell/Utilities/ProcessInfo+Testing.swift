import Foundation

extension ProcessInfo {
    /// Returns true when the process is hosted by XCTest.
    static var isRunningTests: Bool {
        processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
