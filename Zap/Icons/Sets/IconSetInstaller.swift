import Foundation

/// Downloads an icon theme, keeps the part Zap needs, and throws the rest away.
///
/// The archive goes to a temporary file, `tar` extracts the glob the set declares
/// straight into the set's directory, and the download is deleted — so ~31 MB comes
/// down for Papirus and ~4 MB stays. Nothing is streamed into memory; a theme is
/// larger than anything Zap should hold.
///
/// **This spawns `/usr/bin/tar`, which nothing else in Zap does.** Foundation has no
/// archive API, `Compression` handles raw streams rather than tar containers, and
/// bundling one is out under `AGENTS.md`. `tar` is part of macOS, so no dependency
/// is added — but a subprocess is a real departure from how the rest of this app
/// works, and it is here rather than hidden behind something that reads as if it
/// weren't.
enum IconSetInstaller {

    enum InstallError: Error, Equatable {
        case badURL
        case download(String)
        case extraction(String)
        /// `tar` succeeded and produced nothing. Always a wrong `archiveGlob` —
        /// upstream moved its layout, or the row was written from a guess. Loud on
        /// purpose: the alternative is a set that installs cleanly and is empty.
        case nothingMatched(glob: String)

        var message: String {
            switch self {
            case .badURL:
                return "That icon set's address isn't something Zap can fetch."
            case .download(let reason):
                return "Zap couldn't download that icon set. \(reason)"
            case .extraction(let reason):
                return "Zap couldn't unpack that icon set. \(reason)"
            case .nothingMatched:
                return "That icon set didn't contain any icons where Zap expected them. "
                    + "Its layout has probably changed."
            }
        }
    }

    struct Installation: Equatable {
        let set: IconSet
        /// Where the icons ended up.
        let directory: URL
        /// How many were kept.
        let iconCount: Int
        /// The archive's `ETag`, so the next update can ask whether anything changed
        /// instead of downloading 31 MB to find out it hadn't.
        let etag: String?
    }

    /// What an install attempt did.
    enum Outcome: Equatable {
        case installed(Installation)
        /// The server answered the conditional request with 304: what is on disk is
        /// already the current archive, and nothing was downloaded or replaced.
        case unchanged
    }

    /// Fetches `set` and installs it under `directory`, replacing anything there.
    ///
    /// `ifNoneMatch` is the `ETag` of the copy already installed, when there is one.
    /// Passing it turns "update" into a conditional request, so the common case —
    /// checking a theme that hasn't moved — costs a round trip instead of 31 MB.
    static func install(_ set: IconSet, into directory: URL,
                        ifNoneMatch: String? = nil,
                        session: URLSession = .shared) async -> Result<Outcome, InstallError> {
        guard let archiveURL = set.archiveURL else { return .failure(.badURL) }

        let archive: URL
        let etag: String?
        do {
            var request = URLRequest(url: archiveURL)
            if let ifNoneMatch { request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match") }

            let (downloaded, response) = try await session.download(for: request)
            archive = downloaded
            let http = response as? HTTPURLResponse
            etag = http?.value(forHTTPHeaderField: "ETag")

            if http?.statusCode == 304 {
                try? FileManager.default.removeItem(at: archive)
                return .success(.unchanged)
            }
            if let http, !(200..<300).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: archive)
                return .failure(.download("The server returned HTTP \(http.statusCode)."))
            }
        } catch {
            return .failure(.download(error.localizedDescription))
        }
        // Whatever happens next, the 31 MB does not stay.
        defer { try? FileManager.default.removeItem(at: archive) }

        // Unpacked beside the real directory and swapped in only once it has
        // icons in it. Extracting over the installed copy would mean a failed
        // *update* — a bad glob, a truncated archive, a full disk — leaves the user
        // with no theme where they had a working one, and the failure they see says
        // nothing was changed. Staging is what makes that true.
        let staging = directory.deletingLastPathComponent()
            .appendingPathComponent(".\(directory.lastPathComponent).incoming", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        defer { try? FileManager.default.removeItem(at: staging) }

        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return .failure(.extraction(error.localizedDescription))
        }

        switch await extract(archive: archive, matching: set.archiveGlob,
                             strippingComponents: set.strippedComponents, into: staging) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        let icons = installedIconNames(in: staging)
        guard !icons.isEmpty else { return .failure(.nothingMatched(glob: set.archiveGlob)) }

        do {
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.moveItem(at: staging, to: directory)
        } catch {
            return .failure(.extraction(error.localizedDescription))
        }
        return .success(.installed(Installation(set: set, directory: directory,
                                                iconCount: icons.count, etag: etag)))
    }

    /// The icon names installed in `directory` — file names without `.svg`.
    ///
    /// Themes alias heavily by symlink (`chromium.svg → chromium-browser.svg`), and
    /// a selective extraction can leave some of those pointing at a file it didn't
    /// take. `fileExists` follows the link — unlike `URL`'s resource values, which
    /// answer about the link itself — so an alias that still resolves is kept, being
    /// a real and differently-named icon, and a dangling one is dropped here rather
    /// than becoming a search result that can't be rendered.
    static func installedIconNames(in directory: URL) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        let svg = contents.filter { $0.pathExtension.lowercased() == "svg" }
        return Set(svg.filter { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && !isDirectory.boolValue
        }.map { $0.deletingPathExtension().lastPathComponent })
    }

    // MARK: tar

    /// Runs `tar`, extracting only what `glob` matches.
    ///
    /// Off the cooperative pool on a dispatch queue, because the work below is
    /// blocking — reading a pipe to EOF and then waiting on a process — and Swift
    /// concurrency's pool has one thread per core to lose. Unpacking a theme takes
    /// long enough to be worth not taking one of them.
    private static func extract(archive: URL, matching glob: String,
                                strippingComponents: Int,
                                into directory: URL) async -> Result<Void, InstallError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: extractSynchronously(
                    archive: archive, matching: glob,
                    strippingComponents: strippingComponents, into: directory))
            }
        }
    }

    /// `--strip-components` is what flattens the theme's own directory tree away, so
    /// the icons land as bare file names and nothing downstream has to know how the
    /// archive was laid out.
    private static func extractSynchronously(archive: URL, matching glob: String,
                                             strippingComponents: Int,
                                             into directory: URL) -> Result<Void, InstallError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-xzf", archive.path,
            "--strip-components=\(strippingComponents)",
            "-C", directory.path,
            glob,
        ]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            return .failure(.extraction(error.localizedDescription))
        }
        // Read before waiting: a full pipe buffer would deadlock the child.
        let stderrData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let reason = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "tar exited \(process.terminationStatus)"
            NSLog("Zap: tar failed extracting an icon set: %@", reason)
            return .failure(.extraction(reason))
        }
        return .success(())
    }
}
