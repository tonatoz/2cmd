import Foundation
import TwoCmdCore

/// Asks the GitHub releases API whether a newer version exists.
///
/// Plain `URLSession` against the public API — no Sparkle, no appcast, no keys. The app
/// never installs anything by itself: it only offers to open the release page.
enum UpdateChecker {
    static let repository = "tonatoz/2cmd"

    struct Release {
        let version: Version
        let tag: String
        let pageURL: URL
    }

    enum Failure: LocalizedError {
        case noRelease
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noRelease: return "No published releases yet."
            case .badResponse: return "Unexpected response from GitHub."
            }
        }
    }

    static var currentVersion: Version? {
        guard let string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else {
            return nil
        }
        return Version(string)
    }

    /// Calls back on the main queue with the newest release, or `nil` when the running
    /// build is already current.
    static func check(completion: @escaping (Result<Release?, Error>) -> Void) {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result = Self.interpret(data: data, response: response, error: error)
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private static func interpret(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> Result<Release?, Error> {
        if let error { return .failure(error) }

        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return .failure(Failure.noRelease)
        }

        guard let data,
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = payload["tag_name"] as? String,
            let page = payload["html_url"] as? String,
            let pageURL = URL(string: page),
            let latest = Version(tag)
        else {
            return .failure(Failure.badResponse)
        }

        guard let current = currentVersion, latest > current else {
            return .success(nil)
        }
        return .success(Release(version: latest, tag: tag, pageURL: pageURL))
    }
}
