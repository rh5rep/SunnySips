import Foundation

enum AppConfig {
    static let apiBaseURL: URL? = {
        if let raw = ProcessInfo.processInfo.environment["SUNNYSIPS_API_BASE_URL"],
           let url = URL(string: raw) {
            return url
        }
        return nil
    }()

    static let snapshotBaseURL: URL = {
        if let raw = ProcessInfo.processInfo.environment["SUNNYSIPS_SNAPSHOT_BASE_URL"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://rh5rep.github.io/SunnySips/latest")!
    }()

    static let requestLimit = 1200
}
