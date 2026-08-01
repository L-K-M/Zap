import Foundation

/// Fetches image bytes for an icon dragged or pasted in from a browser
/// (`UNJAILED.md §5.3`).
///
/// The design note this implements is that there is no free, keyless, durable
/// general image search left to build on — but the *browser* still has one, with
/// Google Images' transparency filter in its own UI, unmetered and with no key. So
/// Zap doesn't search: it ingests. The user finds the icon where searching is
/// still free, drags it over, and Zap does the validation, normalisation, storage
/// and attribution capture.
///
/// The honest cost of accepting a dragged URL is that Zap now fetches remote
/// bytes, which is what pulls §6.4's untrusted-decode hardening forward into this
/// phase. The cap here is the first half of that; `IconImageValidator` is the rest.
enum RemoteIconFetcher {

    enum FetchError: Error, Equatable {
        case unsupportedScheme
        case requestFailed(status: Int)
        case tooLarge(limit: Int)
        case transport(String)

        var message: String {
            switch self {
            case .unsupportedScheme:
                return "That link isn't an http(s) URL."
            case .requestFailed(let status):
                return "The server returned HTTP \(status)."
            case .tooLarge(let limit):
                return "That image is over the \(limit / (1024 * 1024)) MB limit."
            case .transport(let description):
                return "Couldn't download that image: \(description)"
            }
        }
    }

    /// Downloads `url`, refusing to hold more than `limit` bytes.
    ///
    /// Counted as the bytes arrive rather than read off `Content-Length`: a header
    /// is a claim, and a hostile or chunked response can simply not make it. The
    /// per-byte loop is slower than a bulk read would be, which is a fair trade at
    /// icon sizes — the cap is the point, and anything approaching it is being
    /// rejected anyway.
    static func fetch(_ url: URL,
                      limit: Int = IconImageValidator.Limits.maximumSourceBytes,
                      session: URLSession = .shared) async -> Result<Data, FetchError> {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedScheme)
        }

        do {
            var request = URLRequest(url: url)
            // Nothing about the user's machine or app list goes out with this — see
            // §5.5. It's a plain GET for one image the user already chose.
            request.setValue("image/*", forHTTPHeaderField: "Accept")

            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return .failure(.requestFailed(status: http.statusCode))
            }

            var data = Data()
            data.reserveCapacity(min(limit, 1 << 20))
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit { return .failure(.tooLarge(limit: limit)) }
            }
            return .success(data)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    /// Whether `url` is something this fetcher will even attempt.
    static func isFetchable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
